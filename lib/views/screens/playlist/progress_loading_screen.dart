import 'package:flutter/material.dart';
import 'package:another_iptv_player/controllers/iptv_controller.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/progress_step.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/views/screens/home/home_screen.dart';
import 'package:provider/provider.dart';

class ProgressLoadingScreen extends StatefulWidget {
  final Playlist playlist;
  bool refreshAll = false;

  ProgressLoadingScreen({
    super.key,
    required this.playlist,
    bool refreshAll = false,
  }) {
    this.refreshAll = refreshAll;
  }

  @override
  _ProgressLoadingScreenState createState() => _ProgressLoadingScreenState();
}

class _ProgressLoadingScreenState extends State<ProgressLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseAnimationController;
  late AnimationController _waveAnimationController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late IptvController _controller;

  final Map<ProgressStep, String> stepTitles = {
    ProgressStep.userInfo: 'Bağlantı kuruluyor',
    ProgressStep.categories: 'Kategoriler hazırlanıyor',
    ProgressStep.liveChannels: 'Canlı kanallar yükleniyor',
    ProgressStep.movies: 'Film kütüphanesi açılıyor',
    ProgressStep.series: 'Dizi arşivi hazırlanıyor',
  };

  final Map<ProgressStep, IconData> stepIcons = {
    ProgressStep.userInfo: Icons.wifi,
    ProgressStep.categories: Icons.category,
    ProgressStep.liveChannels: Icons.live_tv,
    ProgressStep.movies: Icons.movie,
    ProgressStep.series: Icons.tv,
  };

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: Duration(milliseconds: 3000),
      vsync: this,
    );

    _pulseAnimationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _waveAnimationController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveAnimationController, curve: Curves.linear),
    );

    final repository = IptvRepository(
      ApiConfig(
        baseUrl: widget.playlist.url!,
        username: widget.playlist.username!,
        password: widget.playlist.password!,
      ),
      widget.playlist.id,
    );
    _controller = IptvController(repository, widget.refreshAll);

    _startLoading();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseAnimationController.dispose();
    _waveAnimationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startLoading() async {
    final success = await _controller.loadAllData();

    if (success) {
      _animationController.animateTo(1.0);
      _pulseAnimationController.stop();
      _waveAnimationController.stop();
      await Future.delayed(Duration(milliseconds: 800));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => ChangeNotifierProvider.value(
            value: _controller,
            child: HomeScreen(),
          ),
        ),
        (route) => false,
      );
    }
  }

  double _getProgressValue(ProgressStep step) {
    switch (step) {
      case ProgressStep.userInfo:
        return 0.2;
      case ProgressStep.categories:
        return 0.4;
      case ProgressStep.liveChannels:
        return 0.6;
      case ProgressStep.movies:
        return 0.8;
      case ProgressStep.series:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
          ),
        ),
        child: ChangeNotifierProvider.value(
          value: _controller,
          child: Consumer<IptvController>(
            builder: (context, controller, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _animationController.animateTo(
                  _getProgressValue(controller.currentStep),
                );
              });

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Section - Logo
                      Column(
                        children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulseAnimation.value,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Color(0xFF00d4ff),
                                        Color(0xFF0099cc),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(
                                          0xFF00d4ff,
                                        ).withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.play_circle_filled,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 24),
                          Text(
                            'IPTV Player',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Premium Streaming Experience',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),

                      // Middle Section - Current Step
                      Column(
                        children: [
                          // Wave Animation
                          AnimatedBuilder(
                            animation: _waveAnimation,
                            builder: (context, child) {
                              return SizedBox(
                                width: 200,
                                height: 200,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer waves
                                    for (int i = 0; i < 3; i++)
                                      Transform.scale(
                                        scale:
                                            1 +
                                            (i * 0.3) +
                                            (_waveAnimation.value * 0.5),
                                        child: Container(
                                          width: 120 + (i * 20),
                                          height: 120 + (i * 20),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Color(0xFF00d4ff)
                                                  .withOpacity(
                                                    (1 - _waveAnimation.value) *
                                                        (0.3 - i * 0.1),
                                                  ),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Center icon
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF00d4ff),
                                            Color(0xFF0099cc),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        stepIcons[controller.currentStep],
                                        size: 40,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          SizedBox(height: 32),

                          Text(
                            stepTitles[controller.currentStep]!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          SizedBox(height: 40),

                          // Progress indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: ProgressStep.values.map((step) {
                              bool isActive =
                                  step.index <= controller.currentStep.index;
                              bool isCurrent = step == controller.currentStep;

                              return AnimatedContainer(
                                duration: Duration(milliseconds: 300),
                                margin: EdgeInsets.symmetric(horizontal: 4),
                                width: isCurrent ? 32 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: isActive
                                      ? Color(0xFF00d4ff)
                                      : Colors.white.withOpacity(0.3),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),

                      // Bottom Section - Progress
                      Column(
                        children: [
                          AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _progressAnimation.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF00d4ff),
                                              Color(0xFF0099cc),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    '${(_progressAnimation.value * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF00d4ff),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          // Error handling
                          if (controller.errorMessage != null) ...[
                            SizedBox(height: 32),
                            Container(
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 32,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Bir hata oluştu',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    controller.errorMessage!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => HomeScreen(),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF00d4ff),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text('Kapat'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
