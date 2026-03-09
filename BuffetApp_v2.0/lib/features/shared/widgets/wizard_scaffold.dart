import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Widget reutilizable estilo wizard profesional (tipo Dynamics 365 / SAP).
///
/// Características:
/// - Barra horizontal de pasos con estados (completado/activo/pendiente)
/// - Contenedor central con ancho máximo responsive
/// - Botones fijos abajo (Volver / Siguiente)
/// - Soporte Enter para avanzar en PC
/// - Adaptación automática PC vs móvil
class WizardScaffold extends StatelessWidget {
  /// Título principal del wizard
  final String title;

  /// Lista de definiciones de pasos
  final List<WizardStepDef> steps;

  /// Índice del paso actual (0-based)
  final int currentStep;

  /// Callback al avanzar al siguiente paso
  final VoidCallback? onNext;

  /// Callback al volver al paso anterior
  final VoidCallback? onBack;

  /// Callback al cancelar el wizard
  final VoidCallback? onCancel;

  /// Si el wizard está procesando (deshabilita botones)
  final bool isLoading;

  /// Texto personalizado para el botón de avanzar (último paso)
  final String? finalButtonText;

  /// Icono del botón final
  final IconData? finalButtonIcon;

  /// Ancho máximo del contenedor central
  final double maxWidth;

  /// Si se permite avanzar con Enter (útil en PC)
  final bool allowEnterToAdvance;

  const WizardScaffold({
    super.key,
    required this.title,
    required this.steps,
    required this.currentStep,
    this.onNext,
    this.onBack,
    this.onCancel,
    this.isLoading = false,
    this.finalButtonText,
    this.finalButtonIcon,
    this.maxWidth = 700,
    this.allowEnterToAdvance = true,
  });

  bool get _isFirstStep => currentStep == 0;
  bool get _isLastStep => currentStep == steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: allowEnterToAdvance,
      onKeyEvent: (event) {
        if (allowEnterToAdvance &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !isLoading &&
            onNext != null) {
          onNext!();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancelar',
            onPressed: onCancel ?? () => Navigator.of(context).pop(),
          ),
          elevation: 1,
        ),
        body: Column(
          children: [
            // === BARRA DE PASOS ===
            _WizardStepBar(
              steps: steps,
              currentStep: currentStep,
              isCompact: isCompact,
            ),

            // === CONTENIDO DEL PASO ACTUAL ===
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 16 : 32,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Título del paso
                        _StepHeader(
                          stepNumber: currentStep + 1,
                          totalSteps: steps.length,
                          title: steps[currentStep].title,
                          subtitle: steps[currentStep].subtitle,
                        ),
                        const SizedBox(height: 24),

                        // Contenido scrolleable
                        Expanded(
                          child: SingleChildScrollView(
                            child: steps[currentStep].content,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // === BARRA DE BOTONES FIJA ===
            _WizardBottomBar(
              isFirstStep: _isFirstStep,
              isLastStep: _isLastStep,
              isLoading: isLoading,
              onBack: onBack,
              onNext: onNext,
              onCancel: onCancel ?? () => Navigator.of(context).pop(),
              finalButtonText: finalButtonText,
              finalButtonIcon: finalButtonIcon,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// BARRA DE PASOS HORIZONTAL
// =============================================================================

class _WizardStepBar extends StatelessWidget {
  final List<WizardStepDef> steps;
  final int currentStep;
  final bool isCompact;

  const _WizardStepBar({
    required this.steps,
    required this.currentStep,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 24,
          vertical: 12,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(steps.length * 2 - 1, (index) {
            if (index.isOdd) {
              // Conector entre pasos
              final stepBefore = index ~/ 2;
              final isCompleted = stepBefore < currentStep;
              return _StepConnector(isCompleted: isCompleted);
            }
            final stepIndex = index ~/ 2;
            final step = steps[stepIndex];
            _StepState state;
            if (stepIndex < currentStep) {
              state = _StepState.completed;
            } else if (stepIndex == currentStep) {
              state = _StepState.active;
            } else {
              state = _StepState.pending;
            }

            return _StepIndicator(
              index: stepIndex,
              label: step.label,
              state: state,
              isCompact: isCompact,
            );
          }),
        ),
      ),
    );
  }
}

enum _StepState { completed, active, pending }

class _StepIndicator extends StatelessWidget {
  final int index;
  final String label;
  final _StepState state;
  final bool isCompact;

  const _StepIndicator({
    required this.index,
    required this.label,
    required this.state,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor;
    Color fgColor;
    Color textColor;
    FontWeight textWeight;

    switch (state) {
      case _StepState.completed:
        bgColor = AppColors.ingreso;
        fgColor = Colors.white;
        textColor = AppColors.ingreso;
        textWeight = FontWeight.w500;
        break;
      case _StepState.active:
        bgColor = theme.colorScheme.primary;
        fgColor = theme.colorScheme.onPrimary;
        textColor = theme.colorScheme.primary;
        textWeight = FontWeight.bold;
        break;
      case _StepState.pending:
        bgColor = context.appColors.border;
        fgColor = context.appColors.textMuted;
        textColor = context.appColors.textMuted;
        textWeight = FontWeight.normal;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Círculo con número o check
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isCompact ? 28 : 32,
          height: isCompact ? 28 : 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: state == _StepState.active
                ? [
                    BoxShadow(
                      color: bgColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: state == _StepState.completed
                ? Icon(Icons.check, color: fgColor, size: isCompact ? 16 : 18)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: fgColor,
                      fontSize: isCompact ? 12 : 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        // Label
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: isCompact ? 10 : 12,
            fontWeight: textWeight,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool isCompleted;

  const _StepConnector({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: 32,
        height: 2,
        color: isCompleted ? AppColors.ingreso : context.appColors.border,
      ),
    );
  }
}

// =============================================================================
// CABECERA DEL PASO
// =============================================================================

class _StepHeader extends StatelessWidget {
  final int stepNumber;
  final int totalSteps;
  final String title;
  final String? subtitle;

  const _StepHeader({
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indicador "Paso X de Y"
        Text(
          'Paso $stepNumber de $totalSteps',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        // Título del paso
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Divider(color: theme.dividerColor.withValues(alpha: 0.3)),
      ],
    );
  }
}

// =============================================================================
// BARRA DE BOTONES INFERIOR
// =============================================================================

class _WizardBottomBar extends StatelessWidget {
  final bool isFirstStep;
  final bool isLastStep;
  final bool isLoading;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback onCancel;
  final String? finalButtonText;
  final IconData? finalButtonIcon;

  const _WizardBottomBar({
    required this.isFirstStep,
    required this.isLastStep,
    required this.isLoading,
    this.onBack,
    this.onNext,
    required this.onCancel,
    this.finalButtonText,
    this.finalButtonIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Botón Cancelar (solo en primer paso)
            if (isFirstStep)
              TextButton(
                onPressed: isLoading ? null : onCancel,
                child: const Text('Cancelar'),
              ),

            // Botón Volver (pasos 2+)
            if (!isFirstStep)
              TextButton.icon(
                onPressed: isLoading ? null : onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Volver'),
              ),

            const Spacer(),

            // Botón Siguiente / Final
            if (isLastStep)
              FilledButton.icon(
                onPressed: isLoading ? null : onNext,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(finalButtonIcon ?? Icons.check_circle, size: 18),
                label: Text(
                  isLoading
                      ? 'Procesando...'
                      : (finalButtonText ?? 'Confirmar'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              )
            else
              FilledButton.icon(
                onPressed: isLoading ? null : onNext,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward, size: 18),
                label: Text(isLoading ? 'Procesando...' : 'Siguiente'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODELOS
// =============================================================================

/// Definición de un paso del wizard.
class WizardStepDef {
  /// Texto corto para la barra de pasos (ej: "Tipo", "Datos")
  final String label;

  /// Título completo mostrado como heading del paso
  final String title;

  /// Subtítulo opcional para guiar al usuario
  final String? subtitle;

  /// Widget con el contenido del paso
  final Widget content;

  const WizardStepDef({
    required this.label,
    required this.title,
    this.subtitle,
    required this.content,
  });
}
