package examples.regex;

import java.util.regex.Pattern;
import org.checkerframework.checker.regex.qual.Regex;

/**
 * Regex Checker demo. Expected compile-time errors:
 *   - brokenRegex:       assignment.type.incompatible (string is not a valid regex)
 *   - compileUserInput:  argument.type.incompatible (input is not known to be @Regex)
 */
public class RegexDemo {

    static @Regex String brokenRegex() {
        return "abc(";
    }

    static Pattern compileUserInput(String input) {
        return Pattern.compile(input);
    }
}
