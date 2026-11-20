import 'package:flutter/material.dart';
import 'strings.dart';
import 'tools.dart';
import 'tool_screen.dart';

String catName(BuildContext c, Cat k) => switch (k) {
      Cat.video => t(c, 'أدوات الفيديو', 'Video Tools'),
      Cat.image => t(c, 'أدوات الصور', 'Image Tools'),
      Cat.audio => t(c, 'أدوات الصوت', 'Audio Tools'),
    };

IconData catIcon(Cat k) => switch (k) {
      Cat.video => Icons.movie_outlined,
      Cat.image => Icons.image_outlined,
      Cat.audio => Icons.headphones_outlined,
    };

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int idx = 1;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cat = Cat.values[idx];
    final body = ToolGrid(cat: cat);
    final langBtn = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton.icon(
        icon: const Icon(Icons.language),
        label: Text(isAr ? 'English' : 'عربي'),
        onPressed: () =>
            appLocale.value = Locale(isAr ? 'en' : 'ar'),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Editor',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [langBtn],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                extended: true,
                minExtendedWidth: 210,
                selectedIndex: idx,
                onDestinationSelected: (i) => setState(() => idx = i),
                destinations: [
                  for (final k in Cat.values)
                    NavigationRailDestination(
                        icon: Icon(catIcon(k)), label: Text(catName(context, k)))
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => setState(() => idx = i),
              destinations: [
                for (final k in Cat.values)
                  NavigationDestination(
                      icon: Icon(catIcon(k)), label: catName(context, k))
              ],
            ),
    );
  }
}

class ToolGrid extends StatelessWidget {
  final Cat cat;
  const ToolGrid({super.key, required this.cat});

  @override
  Widget build(BuildContext context) {
    final list = tools.where((x) => x.cat == cat).toList();
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220, mainAxisExtent: 128, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final x = list[i];
        return Card(
          color: cs.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ToolScreen(tool: x))),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(x.icon, color: cs.primary, size: 28),
                    const Spacer(),
                    if (!x.ready)
                      Text(t(context, 'قريبًا', 'Soon'),
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                  ]),
                  const Spacer(),
                  Text(t(context, x.ar, x.en),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
