import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            collapsedHeight: 80,
            floating: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              title: _HeaderText(),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.withOpacity(0.2),
                      Colors.transparent
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _SectionHeader(title: "IN PROGRESS", count: 3),
              _DownloadItem(
                title: "Cyberpunk 2077 Ultimate Edition",
                subtitle: "FitGirl Repack • 38.4GB",
                progress: 0.65,
                speed: "12.4 MB/s",
                status: DownloadStatus.downloading,
              ),
              _Divider(),
              _DownloadItem(
                title: "Red Dead Redemption 2",
                subtitle: "DODI Repack • 112.4GB",
                progress: 0.28,
                speed: "4.2 MB/s",
                status: DownloadStatus.paused,
              ),
              _Divider(),
              _SectionHeader(title: "COMPLETED", count: 5),
              _DownloadItem(
                title: "Elden Ring v1.10",
                subtitle: "FitGirl Repack • 47.8GB",
                progress: 1.0,
                status: DownloadStatus.completed,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 16),
        child: Row(
          children: [
            Text("DOWNLOADS",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.5,
                )),
            Container(
              height: 4,
              width: 48,
              margin: const EdgeInsets.only(left: 16, bottom: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blueAccent, Colors.purpleAccent],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.blueAccent,
                letterSpacing: 2.0,
              )),
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text("$count",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueAccent,
                )),
          ),
        ],
      ),
    );
  }
}

class _DownloadItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  final String? speed;
  final DownloadStatus status;

  const _DownloadItem({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.status,
    this.speed,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Container(
          decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusIndicator(status: status),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  )),
                              const SizedBox(height: 4),
                              Text(subtitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade400,
                                  )),
                            ],
                          ),
                        ),
                        if (status == DownloadStatus.downloading)
                          _SpeedIndicator(speed: speed!),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _ProgressBar(progress: progress),
                  ],
                ),
              ),
              if (status == DownloadStatus.completed)
                Positioned(
                  right: 20,
                  top: 20,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 6),
                        Text("READY",
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      height: 1,
      color: Colors.white.withOpacity(0.1),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final DownloadStatus status;

  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: status == DownloadStatus.downloading
            ? Lottie.asset(
                'assets/animations/download.json',
                width: 32,
                height: 32,
              )
            : status == DownloadStatus.paused
                ? Icon(Icons.pause_circle, color: Colors.amberAccent, size: 32)
                : SizedBox.shrink(),
      ),
    );
  }
}

class _SpeedIndicator extends StatelessWidget {
  final String speed;

  const _SpeedIndicator({required this.speed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(speed,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.blueAccent,
              letterSpacing: -0.5,
            )),
        Text("SPEED",
            style: TextStyle(
              fontSize: 10,
              color: Colors.blueAccent,
              letterSpacing: 1.5,
            )),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        AnimatedFractionallySizedBox(
          widthFactor: progress,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueAccent, Colors.purpleAccent],
              ),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum DownloadStatus { downloading, paused, completed }
