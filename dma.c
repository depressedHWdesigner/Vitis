#include "xaxidma.h"
#include "xparameters.h"
#include "xdebug.h"

#define DDR_BASE_ADDR XPAR_PS7_RAM_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR	(DDR_BASE_ADDR + 0x1000000)

#define RX_BD_SPACE_BASE	(MEM_BASE_ADDR) /*El RX_BD space es el espacio en memoria DDR que asignamos para los BD de recepcion*/
#define RX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0000FFFF)
#define TX_BD_SPACE_BASE	(MEM_BASE_ADDR + 0x00010000)/*El TX BD space es el esapcio en memoria DDR que asignamos para los BD de transmision*/
#define TX_BD_SPACE_HIGH	(MEM_BASE_ADDR + 0x0001FFFF)
#define TX_BUFF_BASE		(MEM_BASE_ADDR + 0x00100000)
#define RX_BUFF_BASE		(MEM_BASE_ADDR + 0x00300000)/*RX_BUFFER_BASE indica donde inicia el primer buffer del buffer space*/
#define RX_BUFFER_HIGH		(MEM_BASE_ADDR + 0x004FFFFF)

#define PKT_LENGTH	0x20 /*El PKT_ LENGTH es el tamaño de los datos que cargamos en cada BD. 0x20h son 32 bita*/
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

int main(void){


	int Status;
	XAxiDma_Config *Config;
	XAxiDma AxiSGDma;
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
		TxBlockAdd += PKT_LENGTH; //Increase Address by packet length
		RxBlockAdd += PKT_LENGTH;

		/*Move to the next BD in the BD Ring*/
		TxBDptr = (XAxiDma_Bd *)XAxiDma_BdRingNext(TxBDringptr, TxBDptr);
		RxBDptr = (XAxiDma_Bd *)XAxiDma_BdRingNext(RxBDringptr, RxBDptr);

		Xil_DCacheFlushRange((UINTPTR)TX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT*BD_NUM);//Size of BD * Number of BD
		Xil_DCacheFlushRange((UINTPTR)RX_BD_SPACE_BASE, XAXIDMA_BD_MINIMUM_ALIGNMENT*BD_NUM);//Size of BD * Number of BD

		/*Preprocessing. Pasamos al los BD Rings los BDs definidos*/
		Status = XAxiDma_BdRingToHw(RxBDringptr, BD_NUM, RxBDptr);//Calculates the last BD in the BD ring to gather all the required info
		Status = XAxiDma_BdRingToHw(TxBDringptr, BD_NUM, TxBDptr);


}
		while(1){

			u32 Statusdma = XAxiDma_ReadReg(XPAR_AXI_DMA_0_DEVICE_ID, S2MM_OFFSET);
			//Miro el estado de SS2M antes de aceptar datos
			if(Statusdma & XAXIDMA_HALTED_MASK){
				xil_printf("DMA S2MM CHANNEL HALTED!\n\r");
			}
			if(Statusdma & XAXIDMA_IDLE_MASK){
				xil_printf("DMA S2MM CHANNEL IDLE!\n\r");
			}

		    Status = XAxiDma_BdRingStart(RxBDringptr);
		    if(Status != XST_SUCCESS ){
				xil_printf("Error al activar el canal de recepcion: %d n\r");
		    }

		    //Miro el estado tras aceptar datos

			if(Statusdma & XAXIDMA_HALTED_MASK){
					xil_printf("DMA S2MM CHANNEL HALTED!\n\r");
			}
			if(Statusdma & XAXIDMA_IDLE_MASK){
				xil_printf("DMA S2MM CHANNEL IDLE!\n\r");
			}



			//Receive data from the ADC
			//For further transmisión copy RX_BUFFER_SPACE content in TX_BUFFER_SPACE
			

    		u32 mm2s_status = XAxiDma_ReadReg(XPAR_AXI_DMA_0_BASEADDR, XAXIDMA_SR_OFFSET);


    		if (mm2s_status & XAXIDMA_IDLE_MASK)
    		    xil_printf("DMA MM2S is IDLE\r\n");
    		else
    		    xil_printf("DMA MM2S is BUSY\r\n");


		      while(XAxiDma_Busy(&AxiSGDma, XAXIDMA_DEVICE_TO_DMA));


		        Xil_DCacheInvalidateRange(RX_BUFF_BASE, PKT_LENGTH*BD_NUM);


		        u32 *data = (u32 *)RX_BUFF_BASE;
		        for(int i=0; i<PKT_LENGTH/4; i++) {
		            xil_printf("DatA %d: %08x\n\r", i, data[i]);
		        }

		        // Restart DMA for reception

		        Status = XAxiDma_BdRingStart(TxBDringptr);//Brings to HW
		        Status = XAxiDma_BdRingStart(RxBDringptr);
		}






}

