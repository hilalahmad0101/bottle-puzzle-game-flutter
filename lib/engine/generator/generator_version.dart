/// Version of the level-generation algorithm AND its tuning tables.
///
/// A level number reproduces the same puzzle only for the same version.
/// Bump this whenever ANY of these change: the PRNG, seed derivation, the
/// difficulty curve, the reverse builder, grading, or acceptance rules.
/// Stored levels keep the version they were made with.
const int kGeneratorVersion = 1;
