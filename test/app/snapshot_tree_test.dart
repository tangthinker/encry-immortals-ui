import 'package:encry_immortals_ui/app/widgets/snapshot_tree.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FileEntry _entry(String path, {bool dir = false, int size = 0}) {
  return FileEntry(
    path: path,
    kind: dir ? 'dir' : 'file',
    mode: 0,
    size: size,
    modTimeNs: 0,
  );
}

void main() {
  testWidgets('文件树默认折叠，展开后显示子项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SnapshotTree(
              entries: [
                _entry('docs', dir: true),
                _entry('docs/a.txt', size: 12),
                _entry('b.txt', size: 34),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('docs'), findsOneWidget);
    expect(find.text('b.txt'), findsOneWidget);
    expect(find.text('a.txt'), findsNothing);

    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);
  });

  testWidgets('搜索显示完整路径', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SnapshotTree(
              entries: [
                _entry('docs', dir: true),
                _entry('docs/a.txt', size: 12),
                _entry('b.txt', size: 34),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'a.txt');
    await tester.pumpAndSettle();
    expect(find.text('docs/a.txt'), findsOneWidget);
  });
}
