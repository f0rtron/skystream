import 'package:flutter/material.dart';
import '../../../../core/models/torrent_status.dart';
import '../../../../core/widgets/marquee_widget.dart'; // Added

class TorrentInfoWidget extends StatelessWidget {
  final TorrentStatus? status;

  const TorrentInfoWidget({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SizedBox(
                  height: 20, // constrain height for marquee
                  child: MarqueeWidget(
                    child: Text(
                      status!.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Speed and Progress
          Row(
            children: [
              _buildStat("Speed", status!.speedString, Icons.download),
              const SizedBox(width: 16),
              _buildStat(
                "Seeds",
                "${status!.seeds} (${status!.peers})",
                Icons.people,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress Bar
          LinearProgressIndicator(
            value: status!.progress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
          const SizedBox(height: 4),
          Text(
            "${(status!.bytesRead / 1024 / 1024).toStringAsFixed(1)} MB / ${(status!.totalSize / 1024 / 1024).toStringAsFixed(1)} MB",
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          Text(
            "State: ${status!.status}",
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
