import 'package:flutter/material.dart';

import 'package:bandroadie/app/models/band.dart';
import 'band_form_screen.dart';

// ============================================================================
// EDIT BAND SCREEN
// Wrapper around BandFormScreen for editing an existing band
// ============================================================================

class EditBandScreen extends StatelessWidget {
  final Band band;

  const EditBandScreen({super.key, required this.band});

  @override
  Widget build(BuildContext context) {
    return BandFormScreen(mode: BandFormMode.edit, initialBand: band);
  }
}
