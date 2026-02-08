import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  // Diagnostic Login Tool
  Future<String?> signInWithGoogle() async {
    print("🔍 [DIAGNOSTIC] Starting Google Sign-In Flow...");
    try {
      // 1. Trigger Google Sign-In Flow
      print("👉 [STEP 1] Requesting User Account via GoogleSignIn...");
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print("⚠️ [CANCELLED] User cancelled the Google Sign-In.");
        return "User Cancelled";
      }
      print("✅ [SUCCESS] Google User Retrieved: ${googleUser.email}");

      // 2. Obtain Auth Details (Tokens)
      print("👉 [STEP 2] Retrieving Authentication Tokens (idToken + accessToken)...");
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      print("✅ [SUCCESS] Tokens Received.");
      print("   > AccessToken: ${googleAuth.accessToken?.substring(0, 10)}...");
      print("   > IdToken: ${googleAuth.idToken?.substring(0, 10)}...");

      // 3. Create Credential for Firebase
      print("👉 [STEP 3] Creating Firebase Credential...");
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Sign In to Firebase
      print("👉 [STEP 4] Signing in to Firebase Auth...");
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      print("✅ [SUCCESS] Firebase Sign-In Complete!");
      print("   > User UID: ${userCredential.user?.uid}");
      print("   > Email: ${userCredential.user?.email}");
      
      return null; // Null means success (no error string)

    } on FirebaseAuthException catch (e) {
      print("❌ [FIREBASE AUTH ERROR] Code: ${e.code}");
      print("   > Message: ${e.message}");
      print("   > Credential: ${e.credential}");
      return "[FIREBASE] ${e.code}: ${e.message}";
      
    } on PlatformException catch (e) {
      print("❌ [PLATFORM ERROR] Code: ${e.code}");
      print("   > Message: ${e.message}");
      print("   > Details: ${e.details}");
      print("   > Stacktrace: ${e.stacktrace}");
      
      // Common hints for "sign_in_failed"
      if (e.code == 'sign_in_failed') {
         print("💡 [HINT] 'sign_in_failed' usually means SHA-1 mismatch or 'google-services.json' issue.");
      }
      return "[PLATFORM] ${e.code}: ${e.message}";
      
    } catch (e) {
      print("❌ [UNKNOWN ERROR] $e");
      return "[UNKNOWN] $e";
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
