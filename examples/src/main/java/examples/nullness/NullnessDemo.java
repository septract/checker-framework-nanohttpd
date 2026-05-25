package examples.nullness;

import org.checkerframework.checker.nullness.qual.Nullable;

/**
 * Nullness Checker demo. Each method below contains a deliberate
 * dereference-of-possibly-null bug. Expected compile-time errors:
 *   - lengthOfMaybeNull: dereference.of.nullable
 *   - shout:             dereference.of.nullable
 */
public class NullnessDemo {

    static @Nullable String maybeNull(boolean condition) {
        return condition ? "yes" : null;
    }

    static int lengthOfMaybeNull(boolean b) {
        String s = maybeNull(b);
        return s.length();
    }

    static String shout(@Nullable String name) {
        return name.toUpperCase();
    }
}
