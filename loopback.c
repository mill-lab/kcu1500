
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

int main(){
  int num = 100;
  int fd_w = open("/dev/xdma0_h2c_0", O_WRONLY);
  int fd_r = open("/dev/xdma0_c2h_0", O_RDONLY);

  int tx[num], rx[num];

  for (int i=0; i<num; i++){
    tx[i] = i;
    rx[i] = 9999;
  }
  
  write(fd_w, tx, 4*num);
  read(fd_r, rx, 4*num);

  for (int i=0; i<num; i++){
    printf("%d %d \n", tx[i], rx[i]);
  }
  
  return 0;
}
