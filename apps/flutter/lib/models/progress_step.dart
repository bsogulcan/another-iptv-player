enum ProgressStep {
  userInfo,
  categories,
  liveChannels,
  movies,
  series
}

class ProgressState {
  final ProgressStep currentStep;
  final bool isCompleted;
  final String? errorMessage;

  ProgressState({
    required this.currentStep,
    this.isCompleted = false,
    this.errorMessage,
  });

  ProgressState copyWith({
    ProgressStep? currentStep,
    bool? isCompleted,
    String? errorMessage,
  }) {
    return ProgressState(
      currentStep: currentStep ?? this.currentStep,
      isCompleted: isCompleted ?? this.isCompleted,
      errorMessage: errorMessage,
    );
  }
}