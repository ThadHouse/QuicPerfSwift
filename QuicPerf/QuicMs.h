//
//  QuicMs.h
//  QuicPerf
//
//  Created by Thad House on 3/21/22.
//

#ifndef QuicMs_h
#define QuicMs_h

#include "stdint.h"

int QUIC_Initialize(void);

int QUIC_Start(void);

void QUIC_Stop(void);

void QUIC_Uninitialize(void);

uint64_t QUIC_GetCount(void);

#endif /* QuicMs_h */
