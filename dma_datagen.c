#include "xaxidma.h"
#include "xparameters.h"
#include "xdebug.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "xil_util.h"
#include "xaxidma_bdring.h"
#include "sleep.h"
#define DDR_BASE_ADDR 	XPAR_PS7_RAM_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR	(DDR_BASE_ADDR + 0x1000000)

#define RX_BD_SPACE_BASE	(MEM_BASE_ADDR) /*El RX_BD space es el espacio en memoria DDR que asignamos para los BD de recepcion*/
#define RX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0000FFFF)
#define TX_BD_SPACE_BASE	(MEM_BASE_ADDR + 0x00010000)/*El TX BD space es el esapcio en memoria DDR que asignamos para los BD de transmision*/
#define TX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0001FFFF)
#define TX_BUFF_BASE		(MEM_BASE_ADDR + 0x00100000)
#define RX_BUFF_BASE		(MEM_BASE_ADDR + 0x00300000)/*RX_BUFFER_BASE indica donde inicia el primer buffer del buffer space*/
#define RX_BUFFER_HIGH		(MEM_BASE_ADDR + 0x004FFFFF)

#define PKT_LENGTH	40
#define BD_NUM		3/*Numero de BD en cada ring*/

/*MM2S CONTROL*/

#define MM2S_CONTROL_REGISTER       0x00    // MM2S_DMACR
#define MM2S_STATUS_REGISTER        0x04    // MM2S_DMASR
#define MM2S_CURDESC                0x08    // must align 0x40 addresses
#define MM2S_CURDESC_MSB            0x0C    // unused with 32bit addresses
#define MM2S_TAILDESC               0x10    // must align 0x40 addresses
#define MM2S_TAILDESC_MSB           0x14    // unused with 32bit addresses

#define SG_CTL                      0x2C    // CACHE CONTROL

/*S2MM CONTROL*/

#define S2MM_CONTROL_REGISTER       0x30    // S2MM_DMACR
#define S2MM_STATUS_REGISTER        0x34    // S2MM_DMASR
#define S2MM_CURDESC                0x38    // must align 0x40 addresses
#define S2MM_CURDESC_MSB            0x3C    // unused with 32bit addresses
#define S2MM_TAILDESC               0x40    // must align 0x40 addresses
#define S2MM_TAILDESC_MSB           0x44    // unused with 32bit addresses

#define S2MM_OFFSET	0x34

#define POLL_TIMEOUT_COUNTER	1000000U

XAxiDma_Config *Config;
XAxiDma AxiSGDma;


int main(void)
{
	int Status;

	Config = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_DEVICE_ID);

	Status = XAxiDma_CfgInitialize(&AxiSGDma, Config);

	if(Status != XST_SUCCESS ){
		xil_printf("Error al iniciar el DMA\n\r");
	}

	XAxiDma_BdRing *RxBDringptr;/*Puntero al BD Ring de recepcion*/
	/*Get the pointers to the rings from the DMA*/

	RxBDringptr = XAxiDma_GetRxRing(&AxiSGDma);

	Status = XAxiDma_BdRingCreate(RxBDringptr, RX_BD_SPACE_BASE, RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT, BD_NUM);
	if(Status != XST_SUCCESS ){
		xil_printf("Error al crear el RX BDRing n\r");
	}

	/*START BUILDING THE BD RINGS*/

	/*We need a variable for the BD and a variable for the address of data*/

	XAxiDma_Bd *RxBDptr;
	UINTPTR RxBlockAdd = RX_BUFF_BASE;

	/*Now we need to allocate the first BD in the BD Ring*/

	Status = XAxiDma_BdRingAlloc(RxBDringptr, BD_NUM, &RxBDptr);/*Alojamos BD_NUM buffer descriptors en el RXBDring*/
	if(Status != XST_SUCCESS ){
		xil_printf("Error al alojar el RX BD n\r");
	}


	for(int i=0; i<BD_NUM;i++){/*Con esto asignas las direcciones y las longitudes de cada uno de los buffers de los anillos de buffer*/

		XAxiDma_BdClear(RxBDptr);

		Status = XAxiDma_BdSetBufAddr(RxBDptr, RxBlockAdd);
		if(Status != XST_SUCCESS ){
				xil_printf("Error al asignar el address del RX BD numero: %d n\r", i);
			}
		Status = XAxiDma_BdSetLength(RxBDptr, PKT_LENGTH, RxBDringptr->MaxTransferLen);
		if(Status != XST_SUCCESS ){
				xil_printf("Error al asignar la longitud del RX BD numero: %d n\r", i);
			}

		RxBlockAdd += PKT_LENGTH;

		/*Move to the next BD in the BD Ring*/
		RxBDptr = (XAxiDma_Bd *)XAxiDma_BdRingNext(RxBDringptr, RxBDptr);

		}
	Xil_DCacheFlushRange((UINTPTR)RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT * BD_NUM);

	/*Preprocessing. Pasamos al los BD Rings los BDs definidos*/
	Status = XAxiDma_BdRingToHw(RxBDringptr, BD_NUM, RxBDptr);//Calculates the last BD in the BD ring to gather all the required info
	if (Status != XST_SUCCESS) {
		xil_printf("Error al pasar BDs de recepcion a HW\n\r");
		return XST_FAILURE;
	}

	Status = XAxiDma_BdRingStart(RxBDringptr);
	if (Status != XST_SUCCESS) {
	    xil_printf("Error al arrancar S2MM\n\r");
	    return XST_FAILURE;
	}


	int ProcessedBdCount = 0;
	int FreeBdCount;
	int TimeOut = POLL_TIMEOUT_COUNTER;
	XAxiDma_Bd *BdPtr;
	XAxiDma_BdRing *RxRingPtr;

	while(1)
	{
		ProcessedBdCount = 0;
		RxRingPtr = XAxiDma_GetRxRing(&AxiSGDma);

		while(XAxiDma_Busy(&AxiSGDma, XAXIDMA_DEVICE_TO_DMA));//Wait for reception to end


		/*Invalidate cache to make sure we read new data*/
		Xil_DCacheInvalidateRange(RX_BD_SPACE_BASE,  XAXIDMA_BD_MINIMUM_ALIGNMENT * BD_NUM);
		Xil_DCacheInvalidateRange(RX_BUFF_BASE,  PKT_LENGTH * BD_NUM);


		/*
		 * Wait until the data has been received by the Rx channel or
		 * 1usec * 10^6 iterations of timeout occurs.
		 */
		while (TimeOut) {
			if ((ProcessedBdCount = XAxiDma_BdRingFromHw(RxRingPtr,
								    XAXIDMA_ALL_BDS,
								    &BdPtr)) != 0)
				break;
			TimeOut--;
			usleep(1U);
		}

		xil_printf("Se completaron %d BDs\n\r", ProcessedBdCount);

		/*Leer datos nuevos*/
	    UINTPTR rx_addr = RX_BUFF_BASE;
	    for (int b = 0; b < ProcessedBdCount; b++) {
		  u32 *data = (u32 *)rx_addr;
		  xil_printf("BD %d:\n\r", b);
		  for (int i = 0; i < PKT_LENGTH / 4; i++) {
			  xil_printf("Dato %d: %08x\n\r", i, data[i]);
		  }
		  rx_addr += PKT_LENGTH;
	  }


		/* Free all processed RX BDs for future transmission */
		Status = XAxiDma_BdRingFree(RxRingPtr, ProcessedBdCount, BdPtr);
		if (Status != XST_SUCCESS) {
			xil_printf("Failed to free %d rx BDs %d\r\n",
			    ProcessedBdCount, Status);
			return XST_FAILURE;
		}

		/* Return processed BDs to RX channel so we are ready to receive new
		 * packets:
		 *    - Allocate all free RX BDs
		 *    - Pass the BDs to RX channel
		 */
		FreeBdCount = XAxiDma_BdRingGetFreeCnt(RxRingPtr);
		Status = XAxiDma_BdRingAlloc(RxRingPtr, FreeBdCount, &BdPtr);
		if (Status != XST_SUCCESS) {
			xil_printf("bd alloc failed\r\n");
			return XST_FAILURE;
		}

		Status = XAxiDma_BdRingToHw(RxRingPtr, FreeBdCount, BdPtr);
		if (Status != XST_SUCCESS) {
			xil_printf("Submit %d rx BDs failed %d\r\n", FreeBdCount, Status);
			return XST_FAILURE;
		}

		Xil_DCacheFlushRange((UINTPTR)RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT * BD_NUM);




	}




	return XST_SUCCESS;
}
