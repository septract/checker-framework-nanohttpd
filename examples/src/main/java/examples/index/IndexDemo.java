package examples.index;

/**
 * Index Checker demo. Expected compile-time errors:
 *   - lastElement: array.access.unsafe.high
 *   - nthChar:     argument.type.incompatible (n not constrained)
 */
public class IndexDemo {

    static int lastElement(int[] arr) {
        return arr[arr.length];
    }

    static char nthChar(String s, int n) {
        return s.charAt(n);
    }
}
