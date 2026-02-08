import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/screens/api_setup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentSlide = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();

  final List<OnboardingSlide> _slides = [
    OnboardingSlide(
      icon: Icons.shield_outlined,
      title: "Your Keys, Your Control",
      description: "We never see or store your API keys.\n\nAll credentials are encrypted locally on your device using military-grade AES-256 encryption.",
      color: Colors.greenAccent,
    ),
    OnboardingSlide(
      icon: Icons.flash_on,
      title: "Direct Execution",
      description: "Trades move from your phone to Binance instantly.\n\nNo middleman. No proxy servers. Zero latency.",
      color: Colors.cyanAccent,
    ),
    OnboardingSlide(
      icon: Icons.security,
      title: "Permission Minimums",
      description: "Only enable 'Spot' and 'Futures' trading.\n\nNEVER enable 'Withdrawals' or 'Universal Transfer' for maximum security.",
      color: Colors.amber,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            
            // Logo/Title
            Text(
              'SNIPER TERMINAL',
              style: GoogleFonts.orbitron(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.greenAccent,
                letterSpacing: 2,
              ),
            ),
            
            const SizedBox(height: 20),
            
            Text(
              'SECURE ONBOARDING',
              style: GoogleFonts.orbitron(
                fontSize: 14,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Carousel
            Expanded(
              child: CarouselSlider.builder(
                carouselController: _carouselController,
                itemCount: _slides.length,
                itemBuilder: (context, index, realIndex) {
                  return _buildSlide(_slides[index]);
                },
                options: CarouselOptions(
                  height: double.infinity,
                  viewportFraction: 0.85,
                  enlargeCenterPage: true,
                  enableInfiniteScroll: false,
                  onPageChanged: (index, reason) {
                    setState(() {
                      _currentSlide = index;
                    });
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Slide Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (index) {
                return Container(
                  width: _currentSlide == index ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentSlide == index 
                        ? Colors.greenAccent 
                        : Colors.grey[800],
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 40),
            
            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  if (_currentSlide < _slides.length - 1)
                    ElevatedButton(
                      onPressed: () {
                        _carouselController.nextPage();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'NEXT',
                        style: GoogleFonts.orbitron(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  
                  if (_currentSlide == _slides.length - 1)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ApiSetupScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'GET STARTED',
                        style: GoogleFonts.orbitron(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 12),
                  
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ApiSetupScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'SKIP',
                      style: GoogleFonts.orbitron(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(OnboardingSlide slide) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        border: Border.all(color: slide.color.withOpacity(0.3), width: 2),
        borderRadius: BorderRadius.circular(20),
        color: slide.color.withOpacity(0.05),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            slide.icon,
            size: 80,
            color: slide.color,
          ),
          
          const SizedBox(height: 40),
          
          Text(
            slide.title,
            style: GoogleFonts.orbitron(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: slide.color,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 30),
          
          Text(
            slide.description,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey[300],
              height: 1.5,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
