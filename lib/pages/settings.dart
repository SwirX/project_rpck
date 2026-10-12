import 'dart:io';

import 'package:flutter/material.dart';
import 'package:project_rpck/classes/caching.dart';
import 'package:project_rpck/pages/downloads.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Settings", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSectionHeader("Appearance"),
          _buildListTile(
            title: "Dark Mode",
            icon: Icons.dark_mode,
            trailing: Switch(value: true, onChanged: (value) {}),
          ),
          _buildListTile(
            title: "Theme Color",
            icon: Icons.palette,
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ),
          const SizedBox(height: 10),
          _buildSectionHeader("General"),
          _buildListTile(
            title: "Notifications",
            icon: Icons.notifications,
            trailing: Switch(value: true, onChanged: (value) {}),
          ),
          _buildListTile(
            title: "Clear Cache",
            icon: Icons.delete,
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
            onTap: () async {
              showAdaptiveDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("Clear Cache"),
                    content:
                        const Text("Are you sure you want to clear the cache?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () async {
                          final caching = Caching();
                          await caching.clearCache();
                          exit(0);
                        },
                        child: const Text("Clear"),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          _buildListTile(
            title: "Manage Downloads",
            icon: Icons.download,
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => DownloadsPage())),
          ),
          const SizedBox(height: 10),
          _buildSectionHeader("About"),
          _buildListTile(
            title: "Privacy Policy",
            icon: Icons.privacy_tip,
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ),
          _buildListTile(
            title: "About App",
            icon: Icons.info,
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required IconData icon,
    Widget? trailing,
    void Function()? onTap,
  }) {
    return Card(
      color: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
