// This is a basic Flutter widget test placeholder for the example app.
import 'package:flutter_test/flutter_test.dart';
import 'package:media_picker_example/main.dart';

void main() {
  testWidgets('demo home loads', (tester) async {
    await tester.pumpWidget(const MediaCompressorDemoApp());
    expect(find.text('media_picker'), findsOneWidget);
    expect(find.text('Pick & compress images'), findsOneWidget);
  });
}
