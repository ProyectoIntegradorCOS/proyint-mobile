import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../services/identity_service.dart';

class MapAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MapAppBar({
    super.key,
    this.userName,
    required this.onRefreshLocation,
    required this.onOpenSettings,
    required this.onOpenVisitPlan,
    required this.onSelectAndLoadHistory,
    required this.onAttemptLogout,
  });

  final String? userName;
  final VoidCallback onRefreshLocation;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenVisitPlan;
  final VoidCallback onSelectAndLoadHistory;
  final VoidCallback onAttemptLogout;

  @override
  Widget build(BuildContext context) {
    final displayName = (userName ?? '').trim().split(RegExp(r'\s+')).firstWhere(
      (part) => part.isNotEmpty,
      orElse: () => '',
    );
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/onp_logo.png',
            height: 32,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Thaqhiri',
                  overflow: TextOverflow.ellipsis,
                ),
                if (displayName.isNotEmpty)
                  Text(
                    'Bienvenido, $displayName',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: const Color.fromARGB(179, 4, 4, 4)),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.my_location),
          tooltip: 'Refrescar ubicación',
          onPressed: onRefreshLocation,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'settings') {
              onOpenSettings();
            } else if (value == 'my_journey') {
              onOpenVisitPlan();
            } else if (value == 'history') {
              onSelectAndLoadHistory();
            } else if (value == 'about') {
              _showAboutDialog(context);
            } else if (value == 'logout') {
              onAttemptLogout();
            }
          },
          itemBuilder: (context) {
            final id = GetIt.I<IdentityService>();
            final items = <PopupMenuEntry<String>>[];
            if (id.hasPermiso('movil.ajustes')) {
              items.add(
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Ajustes'),
                ),
              );
            }
            if (id.hasPermiso('movil.planvisitas') ||
                id.hasPermiso('movil.visita') ||
                id.hasPermiso('movil.programacionhoy')) {
              items.add(
                const PopupMenuItem(
                  value: 'my_journey',
                  child: Text('Mi Jornada'),
                ),
              );
            }
            if (id.hasPermiso('movil.histxfecha')) {
              items.add(
                const PopupMenuItem(
                  value: 'history',
                  child: Text('Historial'),
                ),
              );
            }
            if (items.isNotEmpty) {
              items.add(const PopupMenuDivider());
            }
            items.add(
              const PopupMenuItem(
                value: 'about',
                child: Text('Acerca de'),
              ),
            );
            items.add(
              const PopupMenuItem(
                value: 'logout',
                child: Text('Cerrar sesión'),
              ),
            );
            return items;
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final versionLabel = '${info.version}+${info.buildNumber}';
    // ignore: use_build_context_synchronously
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sobre esta app'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nombre del APP: ONP Thaqhiri'),
            Text('Compilando version: $versionLabel'),
            const Text('Desarrolladores: OTI.ID (CO, SC)'),
            const Text('Área: OTI'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
