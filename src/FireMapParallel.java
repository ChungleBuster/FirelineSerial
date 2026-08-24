/**
 * Parallel Fork/Join version of {@link FireMap}.
 *
 * The landscape generation and per-cell update rules are exactly those of
 * {@link FireMap}; only the timestep update is parallelised. Each timestep
 * forks a {@link FireTask} that recursively divides the grid's rows and
 * updates disjoint row ranges concurrently, joining the results back
 * together into a single {@link FireMap.StepResult}.
 */
public class FireMapParallel extends FireMap {

    public FireMapParallel(int rows, int columns, long seed, Mode mode) {
        super(rows, columns, seed, mode);
    }

    public FireMapParallel(int rows,
                            int columns,
                            long seed,
                            Mode mode,
                            Landscape landscape,
                            Integer ignitionTopRow,
                            Integer ignitionLeftColumn,
                            Integer ignitionPatchSize) {
        super(rows, columns, seed, mode, landscape,
                ignitionTopRow, ignitionLeftColumn, ignitionPatchSize);
    }

    /**
     * Advances the entire grid by one synchronous timestep, updating the
     * interior of the grid in parallel using the Fork/Join framework.
     */
    public final StepResult stepParallel(Mode mode) {
        prepareNextState();

        FireTask rootTask = new FireTask(
                this, mode, 1, getRows() - 1, 1, getColumns() - 1);
        rootTask.fork();
        StepResult result = rootTask.join();

        completeStep();
        return result;
    }
}
