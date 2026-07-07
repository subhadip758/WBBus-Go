import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'core/constants/app_colors.dart';
import 'data/datasources/bus_local_datasource.dart';
import 'data/datasources/ride_tracking_remote_datasource.dart';
import 'data/repositories/bus_repository_impl.dart';
import 'data/repositories/ride_tracking_repository_impl.dart';
import 'domain/repositories/bus_repository.dart';
import 'domain/repositories/ride_tracking_repository.dart';
import 'presentation/providers/bus_search_provider.dart';
import 'presentation/providers/ride_session_provider.dart';
import 'presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Explicit offline persistence: on by default for Android/iOS, but
  // must be set explicitly to also work on Flutter Web.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Anonymous auth gives every install a stable, real Firebase Auth UID.
  // That UID doubles as the crowdsourced "session ID" — Firestore rules
  // enforce that a device can only write ride-contribution documents
  // under its own UID, which is the only spoofing protection possible
  // without requiring verified accounts.
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  final sessionId = FirebaseAuth.instance.currentUser!.uid;

  await Hive.initFlutter();
  await BusLocalDataSource.init();

  final busRepository = BusRepositoryImpl(BusLocalDataSource());
  final rideTrackingRepository = RideTrackingRepositoryImpl(
    RideTrackingRemoteDataSource(firestore: FirebaseFirestore.instance),
  );

  runApp(WestBengalSmartBusApp(
    busRepository: busRepository,
    rideTrackingRepository: rideTrackingRepository,
    sessionId: sessionId,
  ));
}

class WestBengalSmartBusApp extends StatelessWidget {
  final BusRepository busRepository;
  final RideTrackingRepository rideTrackingRepository;
  final String sessionId;

  const WestBengalSmartBusApp({
    super.key,
    required this.busRepository,
    required this.rideTrackingRepository,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<BusRepository>.value(value: busRepository),
        Provider<RideTrackingRepository>.value(value: rideTrackingRepository),
        ChangeNotifierProvider(create: (_) => BusSearchProvider(busRepository)),
        // App-scoped: a ride session must survive screen navigation
        // (a passenger might switch screens mid-ride), so this lives
        // above the navigator, not inside the map screen.
        ChangeNotifierProvider(
          create: (_) => RideSessionProvider(
            rideTrackingRepository,
            sessionId: sessionId,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'West Bengal Smart Bus',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: AppColors.primary,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: AppColors.primary,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
