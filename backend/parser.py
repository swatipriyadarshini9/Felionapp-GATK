"""Pure-Python VCF parser (no cyvcf2 / htslib required on Windows)."""

from __future__ import annotations


def parse_vcf_to_json(vcf_path: str, upload_id: str, chromosome_filter: str | None = "10"):
    """
    Parse a VCF into JSON for the Flutter client.
    When chromosome_filter is set (default '10'), keep only that chromosome.
    """
    variants = []
    try:
        with open(vcf_path, "r", encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 5:
                    continue

                chrom = parts[0].replace("chr", "").replace("CHR", "")
                if chromosome_filter and chrom != str(chromosome_filter).replace("chr", ""):
                    # Also accept unfiltered if file has only other chroms later — skip
                    continue

                try:
                    pos = int(parts[1])
                except ValueError:
                    continue

                variant_id = parts[2] if parts[2] and parts[2] != "." else f"chr{chrom}_{pos}"
                qual = 0.0
                if len(parts) > 5 and parts[5] not in (".", ""):
                    try:
                        qual = round(float(parts[5]), 2)
                    except ValueError:
                        qual = 0.0

                genotype = "-"
                if len(parts) >= 10:
                    format_keys = parts[8].split(":") if len(parts) > 8 else []
                    sample = parts[9].split(":")
                    if "GT" in format_keys:
                        gt_idx = format_keys.index("GT")
                        if gt_idx < len(sample):
                            genotype = sample[gt_idx].replace("|", "/")
                    else:
                        genotype = sample[0].replace("|", "/")

                variants.append(
                    {
                        "variant_id": variant_id,
                        "chromosome": chrom,
                        "position": pos,
                        "genotype": genotype,
                        "qual": qual,
                    }
                )
    except OSError as e:
        raise ValueError(f"Failed to read VCF: {e}") from e

    if not variants and chromosome_filter:
        # Retry without filter so a non-chr10 upload still returns something useful
        return parse_vcf_to_json(vcf_path, upload_id, chromosome_filter=None)

    return {
        "upload_id": upload_id,
        "status": "completed",
        "variant_count": len(variants),
        "variants": variants,
    }
