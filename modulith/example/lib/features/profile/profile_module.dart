import 'package:flutter/widgets.dart';
import 'package:modulith/modulith.dart';

import 'profile_controller.dart';
import 'profile_page.dart';

class ProfileModule extends Module {
  @override
  Widget get view => const ProfilePage();

  @override
  List<Provider<Controller>> get controllers => [
    Provider<ProfileController>.singleton(create: ProfileController.new),
  ];
}
