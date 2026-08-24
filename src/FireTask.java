import java.util.concurrent.RecursiveTask;

/**
 * Divide-and-conquer Fork/Join task that performs one timestep update for a
 * rectangular strip of rows of a {@link FireMap} grid.
 *
 * The strip is recursively split in half by row until it is no larger than
 * {@link #SEQUENTIAL_CUTOFF} rows, at which point it is updated directly via
 * {@link FireMap#updateRegion}. Since disjoint row ranges only read the
 * shared current-state arrays and only write to their own rows of the
 * next-state arrays, sibling tasks can safely run concurrently.
 */
public class FireTask extends RecursiveTask<FireMap.StepResult> {

    static int SEQUENTIAL_CUTOFF = 50000;

    private final FireMap map;
    private final FireMap.Mode mode;
    private final int rowStart;
    private final int rowEnd;
    private final int columnStart;
    private final int columnEnd;

    public FireTask(FireMap map,
                     FireMap.Mode mode,
                     int rowStart,
                     int rowEnd,
                     int columnStart,
                     int columnEnd) {
        this.map = map;
        this.mode = mode;
        this.rowStart = rowStart;
        this.rowEnd = rowEnd;
        this.columnStart = columnStart;
        this.columnEnd = columnEnd;
    }

    @Override
    protected FireMap.StepResult compute() {
        int numberOfRows = rowEnd - rowStart;

        if (numberOfRows <= SEQUENTIAL_CUTOFF) {
            return map.updateRegion(mode, rowStart, rowEnd, columnStart, columnEnd);
        }

        int middleRow = rowStart + numberOfRows / 2;
        FireTask topHalf = new FireTask(
                map, mode, rowStart, middleRow, columnStart, columnEnd);
        FireTask bottomHalf = new FireTask(
                map, mode, middleRow, rowEnd, columnStart, columnEnd);

        topHalf.fork();
        FireMap.StepResult bottomResult = bottomHalf.compute();
        FireMap.StepResult topResult = topHalf.join();

        return FireMap.StepResult.combine(topResult, bottomResult);
    }
}
