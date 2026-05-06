import 'env.dart';

class SupabaseConfig {
  static String get url => Env.requireSupabaseUrl();
  static String get anonKey => Env.requireSupabaseAnonKey();
}
