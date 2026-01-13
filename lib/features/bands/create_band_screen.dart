import 'package:flutter/material.dart';

import 'band_form_screen.dart';

// ============================================================================
// CREATE BAND SCREEN - FIGMA NODE 56-2476
// Wrapper around BandFormScreen for creating a new band
// ============================================================================

class CreateBandScreen extends StatelessWidget {
  const CreateBandScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const BandFormScreen(mode: BandFormMode.create);
  }
}
