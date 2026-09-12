import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/admin/admin_workspace.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(1200, 800)]) {
    testWidgets('admin workspace adapts at ${size.width}px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminWorkspace(
                child: Column(
                  children: [
                    AdminToolbar(
                      leading: const Icon(Icons.tune_rounded),
                      children: const [
                        SizedBox(width: 130, child: TextField()),
                        SizedBox(width: 110, child: TextField()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const AdminSection(
                      title: 'Course catalogue',
                      subtitle: 'Review and publish records',
                      trailing: IconButton(
                        onPressed: null,
                        icon: Icon(Icons.add_rounded),
                      ),
                      child: Text('Workspace content'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Course catalogue'), findsOneWidget);
      expect(find.text('Workspace content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
