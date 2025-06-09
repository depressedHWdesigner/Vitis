#include "xaxidma.h"
#include "xparameters.h"
#include "xdebug.h"
#include "xscugic.h"

#define DDR_BASE_ADDR XPAR_PS7_RAM_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR	(DDR_BASE_ADDR + 0x1000000)

#define RX_BD_SPACE_BASE	(MEM_BASE_ADDR) /*El RX_BD space es el espacio en memoria DDR que asignamos para los BD de recepcion*/
#define RX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0000FFFF)
#define TX_BD_SPACE_BASE	(MEM_BASE_ADDR + 0x00010000)/*El TX BD space es el esapcio en memoria DDR que asignamos para los BD de transmision*/
#define TX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0001FFFF)
#define TX_BUFF_BASE		(MEM_BASE_ADDR + 0x00100000)
#define RX_BUFF_BASE		(MEM_BASE_ADDR + 0x00300000)/*RX_BUFFER_BASE indica donde inicia el primer buffer del buffer space*/
#define RX_BUFFER_HIGH		(MEM_BASE_ADDR + 0x004FFFFF)

#define PKT_LENGTH	40 /*El PKT_ LENGTH es el tamaño de los datos que cargamos en cada BD. 0x20h son 32 bita*/
#define BD_NUM		12/*Numero de BD en cada ring*/

// MM2S CONTROL
#define MM2S_CONTROL_REGISTER       0x00    // MM2S_DMACR
#define MM2S_STATUS_REGISTER        0x04    // MM2S_DMASR
#define MM2S_CURDESC                0x08    // must align 0x40 addresses
#define MM2S_CURDESC_MSB            0x0C    // unused with 32bit addresses
#define MM2S_TAILDESC               0x10    // must align 0x40 addresses
#define MM2S_TAILDESC_MSB           0x14    // unused with 32bit addresses

#define SG_CTL                      0x2C    // CACHE CONTROL

// S2MM CONTROL
#define S2MM_CONTROL_REGISTER       0x30    // S2MM_DMACR
#define S2MM_STATUS_REGISTER        0x34    // S2MM_DMASR
#define S2MM_CURDESC                0x38    // must align 0x40 addresses
#define S2MM_CURDESC_MSB            0x3C    // unused with 32bit addresses
#define S2MM_TAILDESC               0x40    // must align 0x40 addresses
#define S2MM_TAILDESC_MSB           0x44    // unused with 32bit addresses

#define S2MM_OFFSET	0x34

/*INTERRUPTS*/
XAxiDma_Config *Config;
XAxiDma AxiSGDma;
static XScuGic InterruptController;
volatile int Error = 0;
volatile int TxDone = 0;
volatile int RxDone = 0;
#define RESET_TIMEOUT_COUNTER	10000
#define TX_INTR_ID		XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_INTR/*TX interrupt*/
#define RX_INTR_ID		XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR/*RX interrupt*/
#define INTC_DEVICE_ID	XPAR_SCUGIC_SINGLE_DEVICE_ID
#define INTC		XScuGic
#define INTC_HANDLER	XScuGic_InterruptHandler

static void TxIntrHandler(void *Callback);
static void TxCallBack(XAxiDma_BdRing * TxRingPtr);
static void RxIntrHandler(void *Callback);
static void RxCallBack(XAxiDma_BdRing * RxRingPtr);
static int SetupIntrSystem(INTC * IntcInstancePtr,
			   XAxiDma * AxiDmaPtr, u16 TxIntrId, u16 RxIntrId);



int main(void)
{


	Status = SetupIntrSystem(&InterruptController, &AxiSGDma, TX_INTR_ID, RX_INTR_ID);
	XAxiDma_IntrEnable(&AxiSGDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA); // RX
	XAxiDma_IntrEnable(&AxiSGDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE); // TX


	if (Status != XST_SUCCESS) {
		xil_printf("Failed intr setup\r\n");
		return XST_FAILURE;
	}
	u8 *RxPacket = (u8 *)RX_BUFF_BASE;/*Lo que escribamos en RxPacket se escribirá en el RX_BUFF_BASE*/
									  /*Aqui se almacenaran los paquetes del ADC*/
	Xil_DCacheInvalidateRange((UINTPTR)RxPacket, PKT_LENGTH*BD_NUM); /*Esto no lo tengo claro*/

	Config = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_DEVICE_ID);

	Status = XAxiDma_CfgInitialize(&AxiSGDma, Config);

	if(Status != XST_SUCCESS ){
		xil_printf("Error al iniciar el DMA\n\r");
	}

	/*Start building the BD Rings*/
	XAxiDma_BdRing *TxBDringptr; /*Puntero al BD Ring de transmision*/
	XAxiDma_BdRing *RxBDringptr;/*Puntero al BD Ring de recepcion*/

	/*Get the pointers to the rings from the DMA*/
	TxBDringptr = XAxiDma_GetTxRing(&AxiSGDma);
	RxBDringptr = XAxiDma_GetRxRing(&AxiSGDma);

	Status = XAxiDma_BdRingCreate(TxBDringptr, TX_BD_SPACE_BASE, TX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT, BD_NUM);
	if(Status != XST_SUCCESS ){
		xil_printf("Error al crear el TX BDRing n\r");
	}

	Status = XAxiDma_BdRingCreate(RxBDringptr, RX_BD_SPACE_BASE, RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT, BD_NUM);
	if(Status != XST_SUCCESS ){
		xil_printf("Error al crear el RX BDRing n\r");
	}

	/*START BUILDING THE BD RINGS*/

	/*We need a variable for the BD and a variable for the address of data*/

	XAxiDma_Bd *TxBDptr;/*Pointer for the BD inside the BD Ring*/
	XAxiDma_Bd *RxBDptr;
	UINTPTR TxBlockAdd = TX_BUFF_BASE; /*Address of the data*/
	UINTPTR RxBlockAdd = RX_BUFF_BASE;

	/*Now we need to allocate the first BD in the BD Ring*/
	Status = XAxiDma_BdRingAlloc(TxBDringptr, BD_NUM, &TxBDptr);/*Alojamos BD_NUM buffer descriptors en el TXBDring*/
	if(Status != XST_SUCCESS ){
		xil_printf("Error al alojar el TX BD n\r");
	}
	Status = XAxiDma_BdRingAlloc(RxBDringptr, BD_NUM, &RxBDptr);/*Alojamos BD_NUM buffer descriptors en el RXBDring*/
	if(Status != XST_SUCCESS ){
		xil_printf("Error al alojar el RX BD n\r");
	}


	for(int i=0; i<BD_NUM;i++){/*Con esto asignas las direcciones y las longitudes de cada uno de los buffers de los anillos de buffer*/
		  	XAxiDma_BdClear(TxBDptr);
		    XAxiDma_BdClear(RxBDptr);
			Status = XAxiDma_BdSetBufAddr(TxBDptr, TxBlockAdd);
			if(Status != XST_SUCCESS ){
				xil_printf("Error al asignar el address del TX BD numero: %d n\r", i);
			}
			Status = XAxiDma_BdSetLength(TxBDptr, PKT_LENGTH, TxBDringptr->MaxTransferLen);
			if(Status != XST_SUCCESS ){
					xil_printf("Error al asignar la longitud del TX BD numero: %d n\r", i);
				}
			XAxiDma_BdSetCtrl(TxBDptr, XAXIDMA_BD_CTRL_ALL_MASK);

			Status = XAxiDma_BdSetBufAddr(RxBDptr, RxBlockAdd);
			if(Status != XST_SUCCESS ){
					xil_printf("Error al asignar el address del RX BD numero: %d n\r", i);
				}
			Status = XAxiDma_BdSetLength(RxBDptr, PKT_LENGTH, RxBDringptr->MaxTransferLen);
			if(Status != XST_SUCCESS ){
					xil_printf("Error al asignar la longitud del RX BD numero: %d n\r", i);
				}
			XAxiDma_BdSetCtrl(RxBDptr, XAXIDMA_BD_STS_RXEOF_MASK);

			TxBlockAdd += PKT_LENGTH; //Increase Address by packet length
			RxBlockAdd += PKT_LENGTH;

			/*Move to the next BD in the BD Ring*/
			TxBDptr = (XAxiDma_Bd *)XAxiDma_BdRingNext(TxBDringptr, TxBDptr);
			RxBDptr = (XAxiDma_Bd *)XAxiDma_BdRingNext(RxBDringptr, RxBDptr);



		}

	// Flush entire BD rings
	Xil_DCacheFlushRange((UINTPTR)RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT * BD_NUM);
	Xil_DCacheFlushRange((UINTPTR)TX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT * BD_NUM);

	// Flush data buffers
	Xil_DCacheFlushRange((UINTPTR)RX_BUFF_BASE, PKT_LENGTH * BD_NUM);
	Xil_DCacheFlushRange((UINTPTR)TX_BUFF_BASE, PKT_LENGTH * BD_NUM);

	/*Preprocessing. Pasamos al los BD Rings los BDs definidos*/
	Status = XAxiDma_BdRingToHw(RxBDringptr, BD_NUM, RxBDptr);//Calculates the last BD in the BD ring to gather all the required info
	if (Status != XST_SUCCESS) {
	 xil_printf("Failed to queue BD to HW\n\r");
	    return XST_FAILURE;
	}
	/*DEBUGGING*/
	XAxiDma_Bd *RxBDptr_original;
	RxBDptr_original = RxBDptr;

	xil_printf("Pasado a HW BD @%p\n\r", RxBDptr);
	xil_printf("RxBDptr_original: @%p\n\r", RxBDptr_original);



	Status = XAxiDma_BdRingToHw(TxBDringptr, BD_NUM, TxBDptr);
	if (Status != XST_SUCCESS) {
	    xil_printf("Failed to queue BD to HW\n\r");
	    return XST_FAILURE;
	}

	//Miramos el registro de control S2MM (S2MMCR)
	u32 Statusdma = XAxiDma_ReadReg(XPAR_AXI_DMA_0_BASEADDR, S2MM_CONTROL_REGISTER);
	if(Statusdma & 0x1){
		xil_printf("Start DMA operations\n\r");
	}else{
		xil_printf("Stopped DMA operations\n\r");
	}

	Status = XAxiDma_BdRingStart(RxBDringptr);
	if (Status != XST_SUCCESS) {
	    xil_printf("Failed to start S2MM\n\r");
	    return XST_FAILURE;
	}
	Status = XAxiDma_BdRingStart(TxBDringptr);
	if (Status != XST_SUCCESS) {
	    xil_printf("Failed to start S2MM\n\r");
	    return XST_FAILURE;
	}
    if(Status != XST_SUCCESS ){
		xil_printf("Failure when activating reception channel: %d n\r");
    }

    int bd_count = 0;
		while(1){

			u32 dma_ctrl = XAxiDma_ReadReg(XPAR_AXI_DMA_0_BASEADDR, S2MM_CONTROL_REGISTER);
			xil_printf("S2MM control reg: 0x%08x\n\r", dma_ctrl);

			u32 s2mm_status = XAxiDma_ReadReg(XPAR_AXI_DMA_0_BASEADDR, S2MM_OFFSET);

			//xil_printf("S2MM Status: 0x%08x\n\r", s2mm_status);

			if (s2mm_status & XAXIDMA_HALTED_MASK) xil_printf(" - HALTED\n\r");
			if (s2mm_status & XAXIDMA_IDLE_MASK) xil_printf(" - IDLE\n\r");
			if (s2mm_status & XAXIDMA_ERR_INTERNAL_MASK) xil_printf(" - Internal error\n\r");
			if (s2mm_status & XAXIDMA_ERR_SLAVE_MASK) xil_printf(" - Slave error\n\r");
			if (s2mm_status & XAXIDMA_ERR_DECODE_MASK) xil_printf(" - Decode error\n\r");


		    // 1. Wait for BDs to be processed
			//while((XAxiDma_Busy(&AxiSGDma, XAXIDMA_DMA_TO_DEVICE))||(XAxiDma_Busy(&AxiSGDma, XAXIDMA_DEVICE_TO_DMA)));


			while (bd_count == 0) {
			    bd_count = XAxiDma_BdRingFromHw(RxBDringptr, BD_NUM, &RxBDptr);/*Devuelveme los BDs que el HW ha terminado de usar*/
			    //xil_printf("Desde HW BD @%p\n\r", RxBDptr);
		    }


			xil_printf("%d BDs were completed\n\r", bd_count);

		    // 2. Invalidate cache for received data
		    Xil_DCacheInvalidateRange(RX_BUFF_BASE, PKT_LENGTH * bd_count);


		      UINTPTR rx_addr = RX_BUFF_BASE;
		      for (int b = 0; b < bd_count; b++) {
		          u32 *data = (u32 *)rx_addr;
		          xil_printf("BD %d:\n\r", b);
		          for (int i = 0; i < PKT_LENGTH / 4; i++) {
		              xil_printf("Dato %d: %08x\n\r", i, data[i]);
		          }
		          rx_addr += PKT_LENGTH;
		      }

		      XAxiDma_Bd *CurBd = RxBDptr;
		      /*
		      for (int i = 0; i < bd_count; i++) {
		          u32 status = XAxiDma_BdGetSts(CurBd);
		          xil_printf("BD %d status = 0x%08x\r\n", i, status);

		          CurBd = XAxiDma_BdRingNext(RxBDringptr, CurBd);
		      }
		      */

		      /*DEBUGGING*/
		      int valid_bd_count = 0;
		      XAxiDma_Bd *ValidBdPtr = RxBDptr;


		      for (int i = 0; i < bd_count; i++) {
		          u32 status = XAxiDma_BdGetSts(CurBd);
		          xil_printf("BD %d status = 0x%08x\r\n", i, status);

		          if (status & XAXIDMA_BD_STS_COMPLETE_MASK) {
		              valid_bd_count++;
		              ValidBdPtr = CurBd; 
		          } else {
		              xil_printf("BD %d not completed, will not be freed\n\r", i);
		              break; 
		          }

		          CurBd = XAxiDma_BdRingNext(RxBDringptr, CurBd);
		      }

		      if (valid_bd_count > 0) {
		          Status = XAxiDma_BdRingFree(RxBDringptr, valid_bd_count, RxBDptr);
		          if (Status != XST_SUCCESS) {
		              xil_printf("Failed to free RX BD\r\n");
		          }
		      } else {
		          xil_printf("No BD valid to be freed\n\r");
		      }

		      if (valid_bd_count > 0) {
		          Status = XAxiDma_BdRingAlloc(RxBDringptr, valid_bd_count, &RxBDptr);
		          if (Status != XST_SUCCESS) {
		              xil_printf("RX BD reallocate failed\n\r");
		              break;
		          }

		      }

		      /*DEBUGGING*/

/*

			// 4. Free Ring BDs
				Status = XAxiDma_BdRingFree(RxBDringptr, bd_count, RxBDptr);
				if (Status != XST_SUCCESS) {
				    xil_printf("Error al liberar los RX BDs\r\n");
				}
				// 5. Reserva de nuevo BDs para la próxima recepción
				Status = XAxiDma_BdRingAlloc(RxBDringptr, bd_count, &RxBDptr);
				if (Status != XST_SUCCESS) {
					xil_printf("Error al realojar RX BD\n\r");
					break;
				}


*/
				// 6. Reconfigure BDs
				UINTPTR RxBlockAdd = RX_BUFF_BASE;
				XAxiDma_Bd *BdPtr = RxBDptr;



				for (int i = 0; i < valid_bd_count; i++) {
				    Status = XAxiDma_BdSetLength(BdPtr, PKT_LENGTH, RxBDringptr->MaxTransferLen);
				    if (Status != XST_SUCCESS) xil_printf("Error: SetLength BD %d\n\r", i);

				    XAxiDma_BdSetCtrl(BdPtr, 0); 
				    

				    BdPtr = XAxiDma_BdRingNext(RxBDringptr, BdPtr);
				}

				// 7. Refresh cache for new BDs
				Xil_DCacheFlushRange(RX_BUFF_BASE, PKT_LENGTH * valid_bd_count);
				Xil_DCacheFlushRange((UINTPTR)RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT * valid_bd_count);


				// 8. Resend the reused BDs to HW
				Status = XAxiDma_BdRingToHw(RxBDringptr, valid_bd_count, RxBDptr);
				if (Status != XST_SUCCESS) {
					xil_printf("Error al enviar BDs reutilizados al HW\n\r");
					break;
		            }
					RxBDptr = BdPtr;

		}



	return XST_SUCCESS;
}