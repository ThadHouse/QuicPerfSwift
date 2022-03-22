//
//  QuicMs.m
//  QuicPerf
//
//  Created by Thad House on 3/21/22.
//

#include "QuicMs.h"
#include "msquic.h"
#include <stdatomic.h>

static const QUIC_API_TABLE* Api;
static HQUIC Registration = NULL;

int QUIC_Initialize(void) {
    if (Api) {
        return 1;
    }
   QUIC_STATUS Status = MsQuicOpenVersion(2, (const void**)&Api);
    if (QUIC_FAILED(Status)) {
        return 0;
    }
    Status = Api->RegistrationOpen(NULL, &Registration);
    if (QUIC_FAILED(Status)) {
        MsQuicClose(Api);
        Api = NULL;
        return 0;
    }
    return 1;
}

struct QuicStorage {
    HQUIC Conn;
    HQUIC Config;
    HQUIC Stream;
    atomic_bool RefCount;
    atomic_ullong ReceiveCount;
};

static
QUIC_STATUS
ConnCallback(HQUIC Conn, void* Ctx, QUIC_CONNECTION_EVENT* Event) {
    if (Event->Type == QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE) {
        struct QuicStorage* CtxStorage = (struct QuicStorage*)Ctx;
        if (atomic_fetch_sub(&CtxStorage->RefCount, 1) == 1) {
            Api->StreamClose(CtxStorage->Stream);
            Api->ConnectionClose(CtxStorage->Conn);
            Api->ConfigurationClose(CtxStorage->Config);
            free(CtxStorage);
        }
    }
    return QUIC_STATUS_SUCCESS;
}

static
QUIC_STATUS
StreamCallback(HQUIC Stream, void* Ctx, QUIC_STREAM_EVENT* Event) {
    //printf("Stream %d\n", Event->Type);
    if (Event->Type == QUIC_STREAM_EVENT_RECEIVE) {
        uint64_t TotalCount = 0;
        for (uint32_t i = 0; i < Event->RECEIVE.BufferCount; i++) {
            TotalCount += Event->RECEIVE.Buffers[i].Length;
        }
        struct QuicStorage* CtxStorage = (struct QuicStorage*)Ctx;
        atomic_fetch_add(&CtxStorage->ReceiveCount, TotalCount);
    }
    return QUIC_STATUS_SUCCESS;
}

static uint8_t SendBuf[8] = { 255, 255, 255,255,255,255,255,255};
static QUIC_BUFFER SendQBuf;

static struct QuicStorage* Storage = NULL;

int QUIC_Start(void) {
    QUIC_STATUS Status;
    if (Storage != NULL) {
        return 1;
    }
    Storage = malloc(sizeof(struct QuicStorage));
    if (Storage == NULL) {
        return 0;
    }
    memset(Storage, 0, sizeof(*Storage));
    atomic_init(&Storage->RefCount, 2);
    atomic_init(&Storage->ReceiveCount, 0);

    QUIC_BUFFER Alpn;
    Alpn.Buffer = (uint8_t*)"perf";
    Alpn.Length = 4;
    Status = Api->ConfigurationOpen(Registration, &Alpn, 1, NULL, 0, NULL, &Storage->Config);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    QUIC_CREDENTIAL_CONFIG CfgConfig = {0};
    CfgConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION;
    Status = Api->ConfigurationLoadCredential(Storage->Config, &CfgConfig);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    Status = Api->ConnectionOpen(Registration, ConnCallback, Storage, &Storage->Conn);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    Status = Api->StreamOpen(Storage->Conn, QUIC_STREAM_OPEN_FLAG_NONE, StreamCallback, Storage, &Storage->Stream);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    SendQBuf.Length = 8;
    SendQBuf.Buffer = SendBuf;
    Status = Api->StreamSend(Storage->Stream, &SendQBuf, 1, QUIC_SEND_FLAG_FIN, NULL);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    Status = Api->StreamStart(Storage->Stream, QUIC_STREAM_START_FLAG_NONE);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }
    Status = Api->ConnectionStart(Storage->Conn, Storage->Config, QUIC_ADDRESS_FAMILY_UNSPEC, "192.168.1.36", 4433);
    if (QUIC_FAILED(Status)) {
        goto Exit;
    }

Exit:
    if (QUIC_FAILED(Status)) {
        if (Storage->Stream) {
            Api->StreamClose(Storage->Stream);
        }
        if (Storage->Conn) {
            Api->ConnectionClose(Storage->Conn);
        }
        if (Storage->Config) {
            Api->ConfigurationClose(Storage->Config);
        }
        free(Storage);
        Storage = NULL;
        return 0;
    }
    return 1;
}

void QUIC_Stop(void) {
    if (Storage) {
        Api->ConnectionShutdown(Storage->Conn, QUIC_CONNECTION_SHUTDOWN_FLAG_NONE, 0);
        if (atomic_fetch_sub(&Storage->RefCount, 1) == 1) {
            Api->StreamClose(Storage->Stream);
            Api->ConnectionClose(Storage->Conn);
            Api->ConfigurationClose(Storage->Config);
            free(Storage);
        }
    }
    Storage = NULL;
}

void QUIC_Uninitialize(void) {
    if (Api) {
        Api->RegistrationShutdown(Registration, QUIC_CONNECTION_SHUTDOWN_FLAG_NONE, 0);
        Api->RegistrationClose(Registration);
        MsQuicClose(Api);
        Api = NULL;
        Registration = NULL;
    }
}

uint64_t QUIC_GetCount(void) {
    //printf("%llu\n", (unsigned long long)Count);
    if (Storage) {
        return atomic_load(&Storage->ReceiveCount);
    }
    return 0;
}
