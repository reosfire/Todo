import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connection status card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        state.isSignedIn ? Icons.cloud_done : Icons.cloud_off,
                        size: 32,
                        color: state.isSignedIn ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.isSignedIn
                              ? 'Connected to Dropbox'
                              : 'Not connected',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!state.isSignedIn)
                    FilledButton.icon(
                      onPressed: () => state.signIn(),
                      icon: const Icon(Icons.login),
                      label: const Text('Connect to Dropbox'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => state.signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          ),

          // ── Sync actions ──
          if (state.isSignedIn) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Sync now'),
                    subtitle: const Text(
                      'Downloads if remote is newer, uploads otherwise',
                    ),
                    onTap: state.syncing ? null : () => state.sync(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload),
                    title: const Text('Force upload'),
                    subtitle: const Text('Overwrite remote with local data'),
                    onTap: state.syncing ? null : () => state.forceUpload(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_download),
                    title: const Text('Force download'),
                    subtitle: const Text('Overwrite local with remote data'),
                    onTap: state.syncing ? null : () => state.forceDownload(),
                  ),
                ],
              ),
            ),
            if (state.syncing)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],

          // ── Info card ──
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About sync',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your data is stored in Dropbox\'s app folder which is '
                    'only accessible by this app. '
                    'Sync compares timestamps and keeps the most recent version. '
                    'Use force upload/download to manually resolve conflicts.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
