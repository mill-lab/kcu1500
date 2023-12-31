
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

int main(){
  int num = 10;
  int fd_w = open("/dev/xdma0_h2c_0", O_WRONLY);
  int fd_r = open("/dev/xdma0_c2h_0", O_RDONLY);

  if (fd_w < 0){ printf("open h2c failed\n"); return -1; }
  if (fd_r < 0){ printf("open c2h failed\n"); return -1; } 
 
  int tx[num], rx[num];

  for (int i=0; i<num; i++){
    tx[i] = i+256;
    rx[i] = 9999;
  }
  
  int wrote = write(fd_w, tx, 4*num);
  printf("wrote %d\n", wrote);
  
  int got   = read(fd_r, rx, 4*num);
  printf("read %d\n", got);

  for (int i=0; i<num; i++){
    printf("%d %d \n", tx[i], rx[i]);
  }

  close(fd_w);
  close(fd_r);
  
  return 0;
}
