import 'package:flutter/material.dart';

import '../../ui/rpck_top_bar.dart';

/// How to use the app.
///
/// Offered once after onboarding and always reachable from settings. Every
/// section is skippable on its own, and the whole screen can be dismissed,
/// because a guide that insists on being read is a guide nobody reads.
class OnboardingGuide extends StatefulWidget {
  final bool isFirstRun;

  const OnboardingGuide({super.key, this.isFirstRun = false});

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide> {
  final Set<int> _expanded = {0};
  final PageController _pager = PageController();

  static const _sections = <_GuideSection>[
    _GuideSection(
      title: 'Browsing the catalogue',
      icon: Icons.grid_view_rounded,
      points: [
        'Search sits in the top bar. Partial words work, so "cyber" already '
            'narrows the list as you type.',
        'Tiles fill in their artwork the first time they appear, then keep it. '
            'Scrolling fast will not turn into a burst of requests.',
        'Trending sits above the catalogue. A card marked "Repack available" '
            'opens straight into the matching repack.',
      ],
    ),
    _GuideSection(
      title: 'Starting a download',
      icon: Icons.download_rounded,
      points: [
        'Open a repack to see its mirrors, torrent files and magnets.',
        'Torrent files are listed first because they carry embedded trackers '
            'and find the most peers.',
        'Magnets resolve their metadata over the DHT, which takes longer but '
            'works without a mirror.',
      ],
    ),
    _GuideSection(
      title: 'Watching transfers',
      icon: Icons.speed_rounded,
      points: [
        'The download button in the top right has a badge showing how many '
            'transfers are running.',
        'Each card shows live speed, peer counts and how much is left.',
        'Finished transfers stay listed until you clear them from that screen.',
      ],
    ),
    _GuideSection(
      title: 'Keeping the index fresh',
      icon: Icons.refresh_rounded,
      points: [
        'The catalogue is built once and then read from local storage, so '
            'launching is instant.',
        'Reindex from the control under the search bar. It walks every page '
            'again and takes about ninety seconds.',
        'Clear catalogue deletes the stored rows if you want to start over.',
      ],
    ),
    _GuideSection(
      title: 'Settings',
      icon: Icons.settings_rounded,
      points: [
        'The gear button in the top right opens settings.',
        'Download folder shows where payloads land.',
        'Clear cache removes cached pages, not your index.',
      ],
    ),
  ];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            RpckTopBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(true),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 22),
              ),
              trailing: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Color(0xFF6E6E6E)),
                  ),
                ),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _sections.length,
                itemBuilder: (context, index) => _GuidePage(
                  section: _sections[index],
                  index: index,
                  total: _sections.length,
                  expanded: _expanded.contains(index),
                  onToggle: () => setState(() {
                    _expanded.contains(index)
                        ? _expanded.remove(index)
                        : _expanded.add(index);
                  }),
                  onNext: index == _sections.length - 1
                      ? () => Navigator.of(context).pop(true)
                      : () => _pager.nextPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          ),
                  nextLabel: index == _sections.length - 1
                      ? 'Start using it'
                      : 'Next',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection {
  final String title;
  final IconData icon;
  final List<String> points;

  const _GuideSection({
    required this.title,
    required this.icon,
    required this.points,
  });
}

class _GuidePage extends StatelessWidget {
  final _GuideSection section;
  final int index;
  final int total;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final String nextLabel;

  const _GuidePage({
    required this.section,
    required this.index,
    required this.total,
    required this.expanded,
    required this.onToggle,
    required this.onNext,
    required this.nextLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${index + 1} OF $total',
            style: const TextStyle(
              color: Color(0xFF3D8BFF),
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x1F3D8BFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(section.icon, color: const Color(0xFF3D8BFF)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                for (final point in section.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 7, right: 12),
                          child: Icon(Icons.circle, size: 6, color: Color(0xFF3D8BFF)),
                        ),
                        Expanded(
                          child: Text(
                            point,
                            style: const TextStyle(
                              color: Color(0xFFB4B4B4),
                              fontSize: 14.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: onToggle,
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E6E6E)),
                child: Text(expanded ? 'Less' : 'More'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3D8BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                ),
                child: Text(
                  nextLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}