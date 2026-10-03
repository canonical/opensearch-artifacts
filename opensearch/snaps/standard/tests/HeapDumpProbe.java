// Exhaust only this test JVM's small heap so its configured dump path is exercised.
public class HeapDumpProbe {
    public static void main(String[] arguments) {
        Object[] tooLarge = new Object[100_000_000];
        System.out.println(tooLarge.length);
    }
}
