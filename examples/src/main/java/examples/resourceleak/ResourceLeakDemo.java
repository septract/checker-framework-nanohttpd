package examples.resourceleak;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

/**
 * Resource Leak (MustCall) Checker demo. Expected compile-time error:
 *   - readFirstLine: required.method.not.called
 *
 * The BufferedReader's close() obligation is never discharged: no
 * try-with-resources, no explicit close(), no @Owning hand-off.
 */
public class ResourceLeakDemo {

    static String readFirstLine(String path) throws IOException {
        BufferedReader reader = new BufferedReader(new FileReader(path));
        return reader.readLine();
    }
}
