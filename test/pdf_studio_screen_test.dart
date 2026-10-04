import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/data/models/pdf_project.dart';
import 'package:quickshare/data/models/screenshot_item.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/pdf_editor/pdf_editor_view.dart';
import 'package:quickshare/features/pdf_editor/widgets/export_dialog.dart';
import 'package:quickshare/features/pdf_layout/models/layout_preset.dart';
import 'package:quickshare/features/pdf_layout/models/page_geometry.dart';
import 'dart:typed_data';

void main() {
  group('PDF Studio Screen & Layout Workflow Tests', () {
    testWidgets('1. Top Toolbar renders document name, undo/redo, samples, paste, add, export buttons', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top Toolbar controls
      expect(find.byKey(const Key('pdf_file_name_field')), findsOneWidget);
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      expect(find.byIcon(Icons.redo_rounded), findsOneWidget);
      expect(find.text('Load Lab Samples'), findsOneWidget);
      expect(find.text('Paste (Ctrl+V)'), findsOneWidget);
      expect(find.text('Add Images'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);

      // Sub-toolbar controls
      expect(find.text('Page 1 of 1'), findsWidgets);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Fit Page'), findsOneWidget);
      expect(find.text('Margins'), findsOneWidget);
      expect(find.text('Xerox Guide'), findsOneWidget);
    });

    testWidgets('2. Canvas displays TARGET: SLOT 1, sequential fill, and guide toggles', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Slot 1 target indicator
      expect(find.text('TARGET: SLOT 1'), findsOneWidget);
      expect(find.text('Drop Picture Here'), findsOneWidget);
      expect(find.text('Sequential Fill (1 → 2 → 3)'), findsOneWidget);

      // Inactive slot indicators (for default 4-Up preset: slots 2, 3, 4)
      expect(find.text('SLOT 2'), findsOneWidget);
      expect(find.text('Fills after Slot 1'), findsOneWidget);
      expect(find.text('SLOT 3'), findsOneWidget);
      expect(find.text('Fills after Slot 2'), findsOneWidget);
      expect(find.text('SLOT 4'), findsOneWidget);
      expect(find.text('Fills after Slot 3'), findsOneWidget);

      // Toggle Margins guide
      final marginsChip = find.widgetWithText(FilterChip, 'Margins');
      expect(marginsChip, findsOneWidget);
      await tester.tap(marginsChip);
      await tester.pumpAndSettle();

      // Toggle Xerox Guide
      final xeroxChip = find.widgetWithText(FilterChip, 'Xerox Guide');
      expect(xeroxChip, findsOneWidget);
      await tester.tap(xeroxChip);
      await tester.pumpAndSettle();
    });

    testWidgets('3. Per-Page Layout controls update page layout independently', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final engine = TransferEngine();
      engine.stopTimers();

      final page1 = PdfPageModel(
        pageNumber: 1,
        presetType: LayoutPresetType.four,
        geometry: const PageGeometry(paperSize: PaperSize.a4, isLandscape: false),
      );
      final page2 = PdfPageModel(
        pageNumber: 2,
        presetType: LayoutPresetType.two,
        geometry: const PageGeometry(paperSize: PaperSize.letter, isLandscape: true),
      );

      final project = PdfProject(
        title: 'MultiPage_Test_Project',
        pages: [page1, page2],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: PdfEditorView(initialProject: project),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page 1 is active
      expect(find.text('Page 1 Layout'), findsOneWidget);
      expect(find.text('Per-Page'), findsOneWidget);

      // Presets chips available
      expect(find.widgetWithText(ChoiceChip, '1-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '2-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '3-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '4-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '6-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '8-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '10-Up'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Custom'), findsOneWidget);

      // Verify 4-Up is selected on Page 1
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '4-Up')).selected, isTrue);

      // Change Page 1 to 6-Up
      await tester.tap(find.widgetWithText(ChoiceChip, '6-Up'));
      await tester.pumpAndSettle();
      expect(project.pages[0].presetType, equals(LayoutPresetType.six));
      // Page 2 must remain 2-Up (independent layout)
      expect(project.pages[1].presetType, equals(LayoutPresetType.two));

      // Test Margins preset selection
      final smallMarginChip = find.widgetWithText(ChoiceChip, 'Small (18pt)');
      expect(smallMarginChip, findsOneWidget);
      await tester.tap(smallMarginChip);
      await tester.pumpAndSettle();
      expect(project.pages[0].geometry.marginPoints, equals(18.0));

      // Switch to Page 2 via thumbnail
      final page2Thumb = find.text('Page 2');
      expect(page2Thumb, findsOneWidget);
      await tester.tap(page2Thumb);
      await tester.pumpAndSettle();

      // Panel now shows Page 2 Layout
      expect(find.text('Page 2 Layout'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '2-Up')).selected, isTrue);
      // Page 2 orientation is landscape
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Landscape')).selected, isTrue);
    });

    testWidgets('4. Left Panel Thumbnails Bar allows adding and removing pages', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Pages (1)
      expect(find.text('Pages (1)'), findsOneWidget);

      // Add page using plus icon
      final addPageBtn = find.byIcon(Icons.add_circle);
      expect(addPageBtn, findsOneWidget);
      await tester.tap(addPageBtn);
      await tester.pumpAndSettle();

      // Now Pages (2)
      expect(find.text('Pages (2)'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);

      // Remove page using minus icon
      final removePageBtn = find.byIcon(Icons.remove_circle_outline);
      expect(removePageBtn, findsOneWidget);
      await tester.tap(removePageBtn);
      await tester.pumpAndSettle();

      // Returned to Pages (1)
      expect(find.text('Pages (1)'), findsOneWidget);
    });

    testWidgets('5. Export Dialog allows editing filename, validation, and provides export actions', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final engine = TransferEngine();
      engine.stopTimers();

      final dummyImage = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      final project = PdfProject(
        title: 'Network_Security_Lab',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.two,
            images: [
              ScreenshotItem(name: 'wireshark.png', bytes: dummyImage),
            ],
          ),
        ],
      );

      String committedName = '';

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: Scaffold(
              body: ExportDialog(
                project: project,
                initialFileName: 'Network_Security_Lab.pdf',
                onFileNameChanged: (name) => committedName = name,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check dialog elements
      expect(find.text('Export & Share PDF Document'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save Name'), findsOneWidget);
      expect(find.text('Save to Disk'), findsOneWidget);
      expect(find.text('Share PDF'), findsOneWidget);
      expect(find.text('Print / Preview'), findsOneWidget);
      expect(find.text('Send to Device'), findsOneWidget);

      // Verify filename field populated
      final filenameField = find.widgetWithText(TextField, 'Network_Security_Lab.pdf');
      expect(filenameField, findsOneWidget);

      // Edit filename
      await tester.enterText(filenameField, 'Network_Security_Final_v2');
      await tester.pump();

      // Tap Save Name
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Name'));
      await tester.pumpAndSettle();

      expect(committedName, equals('Network_Security_Final_v2.pdf'));
      expect(engine.savedDocumentName, equals('Network_Security_Final_v2.pdf'));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('6. Automatically continue images onto new pages when images exceed layout slots', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);


      // Initialize project with 1 page with single (1-up) preset
      final project = PdfProject(
        title: 'Overflow_Test',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.one, // maxSlots = 1
            images: [],
          ),
        ],
      );

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: PdfEditorView(initialProject: project),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(project.pages.length, 1);

      // 1. Open Add Images panel
      await tester.tap(find.text('Add Images'));
      await tester.pumpAndSettle();

      // 2. Tap Add Sample inside the in-app panel
      await tester.tap(find.text('Add Sample'));
      await tester.pumpAndSettle();

      // 3. Confirm adding to document (Page 1 has 1-up layout, fills slot 1)
      await tester.tap(find.byKey(const Key('add_images_panel_add_btn')));
      await tester.pumpAndSettle();

      expect(project.pages.length, 1);
      expect(project.pages[0].images.length, 1);

      // 4. Open Add Images panel again to add overflow images
      await tester.tap(find.text('Add Images'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Sample'));
      await tester.pumpAndSettle();

      // Confirm adding 2nd image
      await tester.tap(find.byKey(const Key('add_images_panel_add_btn')));
      await tester.pumpAndSettle();

      // Page 1 has 1-up layout (maxSlots = 1), so overflow automatically continued onto Page 2
      expect(project.pages.length, 2);
      expect(project.pages[0].images.length, 1);
      expect(project.pages[1].images.length, 1);
      expect(project.pages[0].pageNumber, 1);
      expect(project.pages[1].pageNumber, 2);
    });

    testWidgets('7. In-App Add Images Selection Panel opens, displays controls, and cancels without modifying document', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final project = PdfProject(
        title: 'Panel_Cancel_Test',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.four,
            images: [],
          ),
        ],
      );

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: PdfEditorView(initialProject: project),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Add Images" button to open in-app panel
      await tester.tap(find.text('Add Images'));
      await tester.pumpAndSettle();

      // Verify panel controls
      expect(find.byKey(const Key('add_images_panel_cancel_btn')), findsOneWidget);
      expect(find.byKey(const Key('add_images_panel_add_btn')), findsOneWidget);
      expect(find.text('Browse More...'), findsOneWidget);

      // Tap Cancel in the panel
      await tester.tap(find.byKey(const Key('add_images_panel_cancel_btn')));
      await tester.pumpAndSettle();

      // Verify panel closed and document is completely unchanged
      expect(find.byKey(const Key('add_images_panel_cancel_btn')), findsNothing);
      expect(project.pages.length, 1);
      expect(project.pages[0].images.length, 0);
    });

    testWidgets('8. Collapsible Page Layout sidebar expands and collapses via edge handle while preserving page layout settings', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final project = PdfProject(
        title: 'Collapsible_Sidebar_Test',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.two,
            geometry: PageGeometry(paperSize: PaperSize.a4, isLandscape: true),
            images: [],
          ),
        ],
      );

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: PdfEditorView(initialProject: project),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Sidebar is initially open
      expect(find.text('Page 1 Layout'), findsOneWidget);
      expect(find.byKey(const Key('collapse_layout_panel_edge_handle')), findsOneWidget);

      // 2. Collapse sidebar
      await tester.tap(find.byKey(const Key('collapse_layout_panel_edge_handle')));
      await tester.pumpAndSettle();

      // 3. Floating expand button is visible on right edge
      expect(find.byKey(const Key('expand_layout_panel_floating_button')), findsOneWidget);

      // 4. Expand sidebar back
      await tester.tap(find.byKey(const Key('expand_layout_panel_floating_button')));
      await tester.pumpAndSettle();

      // 5. Sidebar reopened and settings preserved
      expect(find.text('Page 1 Layout'), findsOneWidget);
      expect(project.pages[0].presetType, LayoutPresetType.two);
      expect(project.pages[0].geometry.paperSize, PaperSize.a4);
      expect(project.pages[0].geometry.isLandscape, isTrue);
    });
  });
}
