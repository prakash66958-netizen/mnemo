/// Shared visual constants for the cloud-backup affordance.
///
/// These constants are the single source of truth for the cloud-backup icon
/// and accent color used by both [Onboarding_Screen] and [Settings_Tab].
/// Consolidating them here makes the byte-identical icon parity required by
/// Requirements 1.4 / 1.7 a compile-time guarantee — a future change to one
/// surface is structurally a change to the other.
library;

import 'package:flutter/material.dart';

/// Icon shown for the cloud-backup affordance on both the onboarding flow
/// and the Settings tab.
const IconData kCloudBackupIcon = Icons.cloud_done_rounded;

/// Brand color used as the icon tint on both surfaces (Google blue).
const Color kCloudBackupAccent = Color(0xFF4285F4);
