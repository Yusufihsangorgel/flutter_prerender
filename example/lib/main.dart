import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// A stock Flutter web app: it never calls `ensureSemantics()`. The
/// flutter_prerender tool enables the accessibility tree from the outside and
/// recovers this content into static HTML, with zero changes to app source.
///
/// The widgets are annotated with `Semantics(headingLevel:)`, [Link] and
/// `Semantics(image:)` so the recovered document has real headings, anchors
/// and image alt text, rather than a flat wall of paragraphs.
void main() => runApp(const CoffeeApp());

/// The example application root.
class CoffeeApp extends StatelessWidget {
  /// Creates the example app.
  const CoffeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Zebrafish Coffee Roasters',
      debugShowCheckedModeBanner: false,
      home: LandingPage(),
    );
  }
}

/// The single landing page rendered by the example.
class LandingPage extends StatelessWidget {
  /// Creates the landing page.
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              headingLevel: 1,
              child: const Text(
                'Quintessential Ethiopian Yirgacheffe',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'We roast marmoset-grade arabica beans in small batches every '
              'Tuesday. Our flagship blend carries notes of bergamot, '
              'persimmon and a faint whisper of petrichor.',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            Semantics(
              headingLevel: 2,
              child: const Text(
                'Why our customers keep coming back',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Free shipping on orders above forty dollars.'),
            const Text('Beans ground to order using a Comandante grinder.'),
            const SizedBox(height: 24),
            Link(
              uri: Uri.parse('/beans/sumatra-mandheling'),
              builder: (context, followLink) => GestureDetector(
                onTap: followLink,
                child: const Text('Read about Sumatra Mandheling'),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              label:
                  'A roasted batch of Kenya AA Nyeri beans cooling on a tray',
              image: true,
              child: Container(width: 240, height: 140, color: Colors.brown),
            ),
          ],
        ),
      ),
    );
  }
}
