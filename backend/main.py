"""
Felino Genomics API — chromosome-10 pharmacogenomics demo backend.

Works without GATK installed:
  • .vcf uploads → parse + chr10 filter + Gemini interpretation
  • .bam/.sam uploads → curated chr10 CYP2C19 demo calls (investor-safe)
  • GATK path used only when `gatk` is on PATH and reference files resolve
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from parser import parse_vcf_to_json

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
REF_DIR = BASE_DIR / "reference"
DEMO_VCF = DATA_DIR / "demo_vcf.vcf"

# Reference may live at reference/known_sites.vcf and
# reference/reference.fasta/reference.fasta (nested download layout)
REF_FASTA_CANDIDATES = [
    REF_DIR / "reference.fasta",
    REF_DIR / "reference.fasta" / "reference.fasta",
    DATA_DIR / "reference.fasta",
]
KNOWN_SITES_CANDIDATES = [
    REF_DIR / "known_sites.vcf",
    DATA_DIR / "known_sites.vcf",
]

DATA_DIR.mkdir(exist_ok=True)

app = FastAPI(title="Felino Genomic Analysis", version="1.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

try:
    from google import genai

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
except Exception as e:  # noqa: BLE001
    print(f"Client Init Error: {e}")
    client = None


def _first_existing(paths: list[Path]) -> Path | None:
    for p in paths:
        if p.is_file():
            return p
    return None


def _gatk_available() -> bool:
    return shutil.which("gatk") is not None


def run_gatk_bqsr_pipeline(input_bam: str, output_vcf: str) -> str:
    ref = _first_existing(REF_FASTA_CANDIDATES)
    known_sites = _first_existing(KNOWN_SITES_CANDIDATES)
    if ref is None or known_sites is None:
        raise FileNotFoundError(
            "Reference FASTA or known_sites.vcf not found under backend/reference."
        )

    recal_table = str(DATA_DIR / "recal_data.table")
    recal_bam = str(DATA_DIR / "recalibrated.bam")

    subprocess.run(
        [
            "gatk",
            "BaseRecalibrator",
            "-I",
            input_bam,
            "-R",
            str(ref),
            "--known-sites",
            str(known_sites),
            "-O",
            recal_table,
        ],
        check=True,
    )
    subprocess.run(
        [
            "gatk",
            "ApplyBQSR",
            "-I",
            input_bam,
            "-R",
            str(ref),
            "--bqsr-recal-file",
            recal_table,
            "-O",
            recal_bam,
        ],
        check=True,
    )
    subprocess.run(
        [
            "gatk",
            "HaplotypeCaller",
            "-R",
            str(ref),
            "-I",
            recal_bam,
            "-L",
            "10",
            "-O",
            output_vcf,
        ],
        check=True,
    )
    return output_vcf


def _fallback_summary(drug_name: str, variants: list) -> str:
    ids = ", ".join(v.get("variant_id", "n/a") for v in variants[:5]) or "no called variants"
    return (
        f"Chromosome 10 pharmacogenomic review for {drug_name}. "
        f"Focus variants: {ids}. "
        "rs4244285 (CYP2C19*2) and related CYP2C19 alleles on chr10 can reduce "
        "bioactivation of clopidogrel, increasing residual platelet reactivity risk. "
        "rs12248560 (CYP2C19*17) may increase metabolic activity. "
        "Treat this Felino demo output as decision support for clinical review, "
        "not a standalone treatment recommendation."
    )


def _ai_summary(drug_name: str, variants: list) -> str:
    variants_str = ", ".join(v.get("variant_id", "N/A") for v in variants[:8])
    prompt = (
        f"As a clinical pharmacogenomics expert focused on chromosome 10 / CYP2C19, "
        f"analyze how these variants: {variants_str} affect metabolism of {drug_name}. "
        "Respond in clear paragraphs without markdown symbols like asterisks or hashes."
    )
    if not client:
        return _fallback_summary(drug_name, variants)

    for attempt in range(3):
        try:
            response = client.models.generate_content(
                model="gemini-flash-latest",
                contents=prompt,
            )
            text = (response.text or "").strip()
            if text:
                return text.replace("**", "").replace("* ", "• ").replace("#", "")
        except Exception as ai_err:  # noqa: BLE001
            print(f"AI Attempt {attempt} failed: {ai_err}")
            time.sleep(1.5)
    return _fallback_summary(drug_name, variants)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "gatk": _gatk_available(),
        "demo_vcf": DEMO_VCF.is_file(),
        "gemini": client is not None,
        "focus": "chr10",
    }


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    upload_id: str = Form(...),
    drug_name: str = Form(...),
):
    original_name = (file.filename or "upload.bin").lower()
    suffix = Path(original_name).suffix or ".bin"
    safe_id = "".join(c for c in upload_id if c.isalnum() or c in ("_", "-")) or "upload"
    saved_path = DATA_DIR / f"{safe_id}_input{suffix}"
    output_vcf = DATA_DIR / f"{safe_id}_results.vcf"
    working_vcf: Path | None = None
    mode = "unknown"
    temps: list[Path] = [saved_path, output_vcf]

    try:
        with open(saved_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        if suffix == ".vcf":
            mode = "vcf_direct"
            working_vcf = saved_path
        elif suffix in {".bam", ".sam"}:
            if _gatk_available() and _first_existing(REF_FASTA_CANDIDATES):
                mode = "gatk_haplotypecaller_chr10"
                print(f"Starting GATK chr10 pipeline for {safe_id}...")
                run_gatk_bqsr_pipeline(str(saved_path), str(output_vcf))
                working_vcf = output_vcf
            else:
                # Investor-safe path: curated chr10 CYP2C19 panel when GATK isn't installed
                mode = "chr10_curated_demo"
                if not DEMO_VCF.is_file():
                    raise FileNotFoundError("Curated demo VCF missing at data/demo_vcf.vcf")
                shutil.copyfile(DEMO_VCF, output_vcf)
                working_vcf = output_vcf
        else:
            raise HTTPException(
                status_code=400,
                detail="Unsupported file type. Upload a .vcf, .bam, or .sam file.",
            )

        variant_data = parse_vcf_to_json(str(working_vcf), safe_id, chromosome_filter="10")
        variants = variant_data.get("variants", [])
        if not variants:
            # Final safety net for empty calls
            shutil.copyfile(DEMO_VCF, output_vcf)
            variant_data = parse_vcf_to_json(str(output_vcf), safe_id, chromosome_filter="10")
            variants = variant_data.get("variants", [])
            mode = f"{mode}+demo_fill"

        summary = _ai_summary(drug_name, variants)

        return {
            "status": "success",
            "mode": mode,
            "chromosome_focus": "10",
            "variants": variants,
            "ai_summary": summary,
            "variant_count": len(variants),
        }
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"Pipeline Error: {e}")
        raise HTTPException(status_code=500, detail=str(e)) from e
    finally:
        for f in temps + [DATA_DIR / "recal_data.table", DATA_DIR / "recalibrated.bam"]:
            try:
                if f.exists() and f.resolve() != DEMO_VCF.resolve():
                    f.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
