
 #include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

int main(){
  int num = 14;
  int fd_w = open("/dev/xdma0_h2c_0", O_WRONLY);
  int fd_r = open("/dev/xdma0_c2h_0", O_RDONLY);

  if (fd_w < 0){ printf("open h2c failed\n"); return -1; }
  if (fd_r < 0){ printf("open c2h failed\n"); return -1; } 
 
  long int tx[num], rx[num];

  /* for (int i=0; i<num; i++){ */
  /*   tx[i] = i+256; */
  /*   rx[i] = 9999; */
  /* } */

  tx[0] = 0x0100000000000001;
  tx[1] = 0;
  tx[2] = 0;
  tx[3] = 0;
  tx[4] = 0;
  tx[5] = 0;
  tx[6] = 0;
  tx[7] = num - 8;
  
  tx[8] = 1+256;
  tx[9] = 2+256;
  tx[10] = 3+256;
  tx[11] = 4+256;
  tx[12] = 5+256;
  tx[13] = 6+256;

  for (int i=0; i<num; i++){
    rx[i] = 9999;
  }
  
  int wrote = write(fd_w, tx, 8*num);
  printf("wrote %d\n", wrote);
  
  int got   = read(fd_r, rx, 8*num);
  printf("read %d\n", got);

  for (int i=0; i<num; i++){
    printf("[%02d] %ld %ld \n", i, tx[i], rx[i]);
  }

  close(fd_w);
  close(fd_r);
  
  return 0;
}
