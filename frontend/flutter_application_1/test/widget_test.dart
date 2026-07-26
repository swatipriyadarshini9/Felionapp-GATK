import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Felino app boots to auth gate / login', (WidgetTester tester) async {
    await tester.pumpWidget(const FelinoGenomicsApp());
    await tester.pump();

    expect(find.textContaining('FELINO'), findsOneWidget);
  });
}
