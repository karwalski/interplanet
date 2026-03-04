package com.interplanet.time;

/**
 * Planet enum for the InterPlanet time library.
 * Moon uses Earth's orbital elements (tidally locked).
 */
public enum Planet {
    MERCURY, VENUS, EARTH, MARS, JUPITER, SATURN, URANUS, NEPTUNE, MOON;

    /** Planet display name. */
    public String displayName() {
        return switch (this) {
            case MERCURY -> "Mercury";
            case VENUS   -> "Venus";
            case EARTH   -> "Earth";
            case MARS    -> "Mars";
            case JUPITER -> "Jupiter";
            case SATURN  -> "Saturn";
            case URANUS  -> "Uranus";
            case NEPTUNE -> "Neptune";
            case MOON    -> "Moon";
        };
    }

    /** Parse a planet from a case-insensitive string. Returns null if unknown. */
    public static Planet fromString(String name) {
        return switch (name.toUpperCase()) {
            case "MERCURY" -> MERCURY;
            case "VENUS"   -> VENUS;
            case "EARTH"   -> EARTH;
            case "MARS"    -> MARS;
            case "JUPITER" -> JUPITER;
            case "SATURN"  -> SATURN;
            case "URANUS"  -> URANUS;
            case "NEPTUNE" -> NEPTUNE;
            case "MOON"    -> MOON;
            default        -> null;
        };
    }
}
