import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Remove source indentation without joining adjacent HTML paragraphs.
String readableReport(String source) {
  final root = html.parseFragment(source);
  final buffer = StringBuffer();
  void visit(Node node) {
    if (node is Text) {
      buffer.write(node.text);
    } else if (node is Element) {
      if (['script', 'style'].contains(node.localName)) return;
      final block = [
        'p',
        'div',
        'section',
        'article',
        'h1',
        'h2',
        'h3',
        'li',
        'blockquote',
      ].contains(node.localName);
      if (block || node.localName == 'br') buffer.write('\n');
      for (final child in node.nodes) {
        visit(child);
      }
      if (block) buffer.write('\n');
    }
  }

  for (final node in root.nodes) {
    visit(node);
  }
  return buffer
      .toString()
      .split(RegExp(r'\r?\n'))
      .map(
        (line) => line
            .replaceAll(RegExp(r'[\s\u00a0\u2000-\u200b\u202f\u3000]+'), ' ')
            .trim(),
      )
      .where((line) => line.isNotEmpty)
      .join('\n\n');
}
