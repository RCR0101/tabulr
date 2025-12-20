import 'package:flutter/material.dart';
import '../services/responsive_service.dart';

class CGPACalculatorScreen extends StatelessWidget {
  const CGPACalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.all(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.calculate,
                  size: ResponsiveService.getValue(context, mobile: 64, tablet: 72, desktop: 80),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 24)),
              Text(
                'CGPA Calculator',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),
              Text(
                'Coming Soon!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 24)),
              Container(
                padding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.all(16),
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.construction,
                      size: ResponsiveService.getValue(context, mobile: 32, tablet: 36, desktop: 40),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                    Text(
                      'We\'re working hard to bring you a comprehensive CGPA calculator.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
                    Text(
                      'Features will include:\n• GPA calculation by semester\n• Overall CGPA tracking\n• Grade predictions\n• Credit hour management',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 32)),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Timetables'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(
                    ResponsiveService.getValue(context, mobile: 200, tablet: 220, desktop: 240),
                    ResponsiveService.getTouchTargetSize(context),
                  ),
                  padding: ResponsiveService.getAdaptivePadding(
                    context,
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}