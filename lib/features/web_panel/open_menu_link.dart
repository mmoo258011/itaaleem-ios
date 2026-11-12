import 'package:flutter/material.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/in_app_web_screen.dart';
import 'package:itaaleem/features/web_panel/web_panel_screen.dart';

/// A server `menu_links` entry: signed in by handoff in [WebPanelScreen]
/// when it asks for it, else the ordinary in-app page.
Future<void> openMenuLink(BuildContext context, MenuLink link) {
  if (link.handoff) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WebPanelScreen(url: link.url, title: link.title),
      ),
    );
  }
  return openConfigLink(context, link.url.toString(), title: link.title);
}
