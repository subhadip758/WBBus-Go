class AppStrings {
  final String appTitle;
  final String from;
  final String to;
  final String searchBus;
  final String popularRoutes;
  final String noResults;
  final String busDetails;
  final String trackLive;
  final String liveNotAvailable;
  final String startSharing;
  final String stopSharing;
  final String driverMode;
  final String stale;

  const AppStrings({
    required this.appTitle,
    required this.from,
    required this.to,
    required this.searchBus,
    required this.popularRoutes,
    required this.noResults,
    required this.busDetails,
    required this.trackLive,
    required this.liveNotAvailable,
    required this.startSharing,
    required this.stopSharing,
    required this.driverMode,
    required this.stale,
  });

  static const en = AppStrings(
    appTitle: 'West Bengal Smart Bus',
    from: 'From',
    to: 'To',
    searchBus: 'Search Bus',
    popularRoutes: 'Popular Routes',
    noResults: 'No buses found for this route yet.',
    busDetails: 'Bus Details',
    trackLive: 'Track Live Location',
    liveNotAvailable: 'No driver is sharing live location for this bus yet.',
    startSharing: 'Start Sharing My Location',
    stopSharing: 'Stop Sharing',
    driverMode: 'Driver Mode',
    stale: 'Location may be outdated',
  );

  static const bn = AppStrings(
    appTitle: 'পশ্চিমবঙ্গ স্মার্ট বাস',
    from: 'কোথা থেকে',
    to: 'কোথায়',
    searchBus: 'বাস খুঁজুন',
    popularRoutes: 'জনপ্রিয় রুট',
    noResults: 'এই রুটে এখনো কোনো বাস পাওয়া যায়নি।',
    busDetails: 'বাসের বিবরণ',
    trackLive: 'লাইভ অবস্থান দেখুন',
    liveNotAvailable: 'এই বাসের জন্য এখনো কোনো চালক লাইভ অবস্থান শেয়ার করছেন না।',
    startSharing: 'আমার অবস্থান শেয়ার শুরু করুন',
    stopSharing: 'শেয়ার বন্ধ করুন',
    driverMode: 'চালক মোড',
    stale: 'অবস্থানটি পুরনো হতে পারে',
  );
}
