import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:diagnosis_odyssey/models/outbreak_intel.dart';
import 'package:diagnosis_odyssey/screens/outbreak_intel_detail_screen.dart';
import 'package:diagnosis_odyssey/widgets/pdb_viewer/pdb_viewer_stub.dart';

import 'helpers/fake_webview_platform.dart';

void main() {
  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });
  const baseIntel = OutbreakIntel(
    id: 'influenza_a',
    name: 'Influenza A',
    commonName: 'Flu',
    rarity: 'common',
    category: 'respiratory',
    heroImage: '',
    model3d: '',
    molecularFormula: 'Influenza A hemagglutinin trimer',
    model3dSource: 'RCSB PDB 1RU7',
    pdbId: '1RU7',
    molecularStructure: 'assets/images/influenza_a_hero.jpg',
    molecularImage: 'assets/images/molecules/influenza_a.jpg',
    description: 'A real respiratory virus.',
    stats: OutbreakIntelStats(
      r0: '1.5',
      incubationDays: '1-4 days',
      severity: 'moderate',
      transmissionRoute: 'droplets',
      vaccineAvailable: true,
    ),
    nationalStats: NationalStats(
      infectants: 12347,
      mortalityRate: '0.02%',
      infectionRate: '1.8%',
      recovered: 11204,
    ),
    clinicalProfile: ClinicalProfile(
      hiddenPeriodDays: '1-4 days',
      variants: 'H1N1',
      severity: 'Moderate',
    ),
    transmissionMedia: ['airborne', 'humanToHuman'],
    cityOutbreaks: [],
    symptoms: ['fever', 'cough'],
    actions: ['rest', 'hydrate'],
    citations: [Citation(text: 'CDC', url: 'https://cdc.gov')],
    unlockCondition: '',
  );

  testWidgets('Detail screen shows stats, symptoms, actions, sources, national snapshot, clinical profile',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OutbreakIntelDetailScreen(intel: baseIntel),
      ),
    );

    expect(find.text('Influenza A'), findsOneWidget);
    expect(find.text('A real respiratory virus.'), findsOneWidget);
    expect(find.text('R0: 1.5'), findsOneWidget);
    expect(find.text('fever'), findsOneWidget);
    expect(find.text('rest'), findsOneWidget);
    expect(find.text('CDC'), findsOneWidget);
    expect(find.text('Live Snapshot'), findsOneWidget);
    expect(find.text('United States'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('Clinical Profile'), findsOneWidget);
  });

  testWidgets('Detail screen renders molecular image card when pdbId is provided',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OutbreakIntelDetailScreen(intel: baseIntel),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3D Protein Structure'), findsOneWidget);
    expect(find.text('Influenza A hemagglutinin trimer'), findsOneWidget);
    expect(find.text('RCSB PDB 1RU7'), findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(1));
  });

  testWidgets('Tapping molecular image opens 3-D molecular viewer dialog',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OutbreakIntelDetailScreen(intel: baseIntel),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Influenza A hemagglutinin trimer'));
    await tester.tap(find.text('Influenza A hemagglutinin trimer'));
    await tester.pumpAndSettle();

    expect(find.byType(PdbViewer), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('Detail screen hides structure section when no model3d or pdbId',
      (WidgetTester tester) async {
    const intel = OutbreakIntel(
      id: 'influenza_a',
      name: 'Influenza A',
      commonName: 'Flu',
      rarity: 'common',
      category: 'respiratory',
      heroImage: '',
      model3d: '',
      molecularFormula: '',
      model3dSource: '',
      pdbId: '',
      molecularStructure: '',
      molecularImage: '',
      description: 'A real respiratory virus.',
      stats: OutbreakIntelStats(
        r0: '1.5',
        incubationDays: '1-4 days',
        severity: 'moderate',
        transmissionRoute: 'droplets',
        vaccineAvailable: true,
      ),
      nationalStats: NationalStats(
        infectants: 12347,
        mortalityRate: '0.02%',
        infectionRate: '1.8%',
        recovered: 11204,
      ),
      clinicalProfile: ClinicalProfile(
        hiddenPeriodDays: '1-4 days',
        variants: 'H1N1',
        severity: 'Moderate',
      ),
      transmissionMedia: ['airborne', 'humanToHuman'],
      cityOutbreaks: [],
      symptoms: ['fever', 'cough'],
      actions: ['rest', 'hydrate'],
      citations: [Citation(text: 'CDC', url: 'https://cdc.gov')],
      unlockCondition: '',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: OutbreakIntelDetailScreen(intel: intel),
      ),
    );

    expect(find.text('3D Protein Structure'), findsNothing);
  });
}
