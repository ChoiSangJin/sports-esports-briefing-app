import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/services/report_text.dart';

void main() {
  test(
    'article indentation and HTML spaces are removed while paragraphs survive',
    () {
      expect(
        readableReport(
          '<p>\n     Added Purdy: &ldquo;Good game.&rdquo;\n</p><p>&nbsp;&nbsp; Kittle had eight catches.</p>',
        ),
        'Added Purdy: “Good game.”\n\nKittle had eight catches.',
      );
      expect(
        readableReport('    Injuries\n\n      Receivers are inactive.'),
        'Injuries\n\nReceivers are inactive.',
      );
    },
  );
}
