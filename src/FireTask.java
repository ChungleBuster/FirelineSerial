
import java.security.KeyStore;
import java.util.concurrent.RecursiveTask;


public class FireTask extends RecursiveTask<StepResult>{
    static int SEQUENTIAL_CUTOFF = 1000;
    private int hi;
    private int lo;
    private double[][] newTemp;
    private double[][] currentTemp;

    public FireTask(double[][] currentTemperature, int l, int h) {
        this.currentTemp = currentTemperature;
        this.lo = l;
        this.hi = h;
    }

    public double[][] getNewTemp(){
        return this.newTemp;
    }

    public void run(){
        if ((hi -lo) < SEQUENTIAL_CUTOFF){
            for (int i = lo; i < hi; i++){
                for (int j = 0; j < arr[i].length; j++){
                        double neighbourAverage =
                        (currentTemperature[i - 1][j]
                         + currentTemperature[i + 1][j]
                         + currentTemperature[i][j - 1]
                         + currentTemperature[i][j + 1]) / 4.0;
                }
            }
        }
    }

    

}