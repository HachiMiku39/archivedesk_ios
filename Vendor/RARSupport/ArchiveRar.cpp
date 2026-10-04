// ArchiveDesk bridge, LGPL-2.1-or-later.
// Uses 7-Zip RAR decoding only. RAR codec sources have the unRAR restriction:
// this code must not be used to develop a RAR (WinRAR) compatible archiver.
#include "ArchiveRar.h"
#include "CPP/Common/MyInitGuid.h"
#include "C/7zCrc.h"
#include "C/Sha1.h"
#include "C/Sha256.h"
#include "CPP/Common/MyCom.h"
#include "CPP/Common/UTFConvert.h"
#include "CPP/Windows/PropVariant.h"
#include "CPP/7zip/IPassword.h"
#include "CPP/7zip/PropID.h"
#include "CPP/7zip/Common/RegisterArc.h"
#include "CPP/7zip/Archive/Rar/RarHandler.h"
#include "CPP/7zip/Archive/Rar/Rar5Handler.h"
// Keep decoder registration in the referenced bridge object, not a discarded
// static-library object. No compression codec or external codec loader exists.
#include "CPP/7zip/Compress/RarCodecsRegister.cpp"
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <algorithm>
#include <memory>
#include <cstring>

using NWindows::NCOM::CPropVariant;
void RegisterArc(const CArcInfo *) throw() {} // Only two directly-created readers.

struct Job {
    ADRContinue proceed;
    void *context;
    bool missingPassword = false, askedPassword = false, cancelled = false;
    bool Continue() {
        if (proceed && !proceed(context)) { cancelled = true; return false; }
        return true;
    }
    HRESULT Password(const char *password, BSTR *result) {
        *result = nullptr; askedPassword = true;
        if (!Continue()) return E_ABORT;
        if (!password) { missingPassword = true; return E_ABORT; }
        UString wide;
        AString encoded(password);
        const bool valid = ConvertUTF8ToUnicode(encoded, wide);
        volatile char *encodedBytes = const_cast<char *>(encoded.Ptr());
        for (unsigned i = 0; i <= encoded.Len(); i++) encodedBytes[i] = 0;
        if (!valid) return E_FAIL;
        *result = SysAllocStringLen(wide.Ptr(), wide.Len());
        volatile wchar_t *bytes = const_cast<wchar_t *>(wide.Ptr());
        for (unsigned i = 0; i <= wide.Len(); i++) bytes[i] = 0;
        return *result ? S_OK : E_OUTOFMEMORY;
    }
};

class Input final : public IInStream, public CMyUnknownImp {
    Z7_IFACES_IMP_UNK_1(IInStream)
    Z7_IFACE_COM7_IMP(ISequentialInStream)
public:
    int fd = -1;
    Job *job;
    Input(int descriptor, Job *j): fd(descriptor), job(j) {}
    ~Input() { if (fd >= 0) close(fd); }
};
Z7_COM7F_IMF(Input::Read(void *data, UInt32 size, UInt32 *processed)) {
    if (processed) *processed = 0;
    if (!job->Continue()) return E_ABORT;
    const ssize_t n = read(fd, data, std::min<UInt32>(size, 256*1024));
    if (n < 0) return E_FAIL;
    if (processed) *processed = (UInt32)n;
    return S_OK;
}
Z7_COM7F_IMF(Input::Seek(Int64 offset, UInt32 origin, UInt64 *position)) {
    if (!job->Continue()) return E_ABORT;
    if (origin > 2) return E_INVALIDARG;
    const off_t pos = lseek(fd, offset, (int)origin);
    if (pos < 0) return E_FAIL;
    if (position) *position = (UInt64)pos;
    return S_OK;
}

class OpenCallback final : public IArchiveOpenCallback, public ICryptoGetTextPassword, public CMyUnknownImp {
    Z7_IFACES_IMP_UNK_2(IArchiveOpenCallback, ICryptoGetTextPassword)
public:
    Job *job;
    const char *password;
    OpenCallback(Job *j, const char *p): job(j), password(p) {}
};
Z7_COM7F_IMF(OpenCallback::SetTotal(const UInt64 *files, const UInt64 *)) {
    if (files && *files > 100000) return E_OUTOFMEMORY;
    return job->Continue() ? S_OK : E_ABORT;
}
Z7_COM7F_IMF(OpenCallback::SetCompleted(const UInt64 *files, const UInt64 *)) {
    if (files && *files > 100000) return E_OUTOFMEMORY;
    return job->Continue() ? S_OK : E_ABORT;
}
Z7_COM7F_IMF(OpenCallback::CryptoGetTextPassword(BSTR *result)) { return job->Password(password, result); }

class Output final : public ISequentialOutStream, public CMyUnknownImp {
    Z7_IFACES_IMP_UNK_1(ISequentialOutStream)
public:
    Job *job;
    ADRWrite write;
    void *context;
    UInt64 expected = 0, actual = 0;
};
Z7_COM7F_IMF(Output::Write(const void *data, UInt32 size, UInt32 *processed)) {
    if (processed) *processed = 0;
    if (!job->Continue()) return E_ABORT;
    if ((UInt64)size > expected - actual) return E_FAIL;
    const Byte *bytes = (const Byte *)data;
    UInt32 offset = 0;
    while (offset < size) {
        if (!job->Continue()) return E_ABORT;
        const UInt32 count = std::min<UInt32>(size-offset, 256*1024);
        if (write(context, bytes+offset, count) != 0) return E_ABORT;
        offset += count;
    }
    actual += size;
    if (processed) *processed = size;
    return S_OK;
}

class ExtractCallback final : public IArchiveExtractCallback, public ICryptoGetTextPassword, public CMyUnknownImp {
    Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
    Z7_IFACE_COM7_IMP(IProgress)
public:
    Job *job;
    const char *password;
    UInt32 index;
    CMyComPtr<ISequentialOutStream> output;
    int error = 0;
    bool targetSeen = false;
};
Z7_COM7F_IMF(ExtractCallback::SetTotal(UInt64)) { return job->Continue() ? S_OK : E_ABORT; }
Z7_COM7F_IMF(ExtractCallback::SetCompleted(const UInt64 *)) { return job->Continue() ? S_OK : E_ABORT; }
Z7_COM7F_IMF(ExtractCallback::GetStream(UInt32 current, ISequentialOutStream **stream, Int32 mode)) {
    *stream = nullptr;
    if (!job->Continue()) return E_ABORT;
    if (current == index && mode == NArchive::NExtract::NAskMode::kExtract) {
        *stream = output; (*stream)->AddRef(); targetSeen = true;
    }
    return S_OK;
}
Z7_COM7F_IMF(ExtractCallback::PrepareOperation(Int32)) { return job->Continue() ? S_OK : E_ABORT; }
Z7_COM7F_IMF(ExtractCallback::SetOperationResult(Int32 result)) {
    if (result != NArchive::NExtract::NOperationResult::kOK) error = ADR_PASSWORD_OR_DAMAGE;
    return job->Continue() ? S_OK : E_ABORT;
}
Z7_COM7F_IMF(ExtractCallback::CryptoGetTextPassword(BSTR *result)) { return job->Password(password, result); }

struct Handle {
    Job job;
    CMyComPtr<IInStream> input;
    CMyComPtr<IInArchive> archive;
    uint32_t count = 0;
    bool encryptedHeaders = false;
    int version = 4;
    ~Handle() { if (archive) archive->Close(); }
};
static int status(HRESULT hr, const Job &job) {
    if (job.cancelled) return ADR_CANCELLED;
    if (job.missingPassword) return ADR_PASSWORD_REQUIRED;
    if (hr == E_OUTOFMEMORY) return ADR_CAPACITY;
    if (hr != S_OK) return ADR_PASSWORD_OR_DAMAGE;
    return ADR_OK;
}
static CPropVariant property(Handle *h, UInt32 index, PROPID id, bool archive = false) {
    CPropVariant value;
    HRESULT hr = archive ? h->archive->GetArchiveProperty(id, &value) : h->archive->GetProperty(index, id, &value);
    if (hr != S_OK) throw int(ADR_MALFORMED);
    return value;
}
static bool truth(const CPropVariant &v) { return v.vt == VT_BOOL && v.boolVal != VARIANT_FALSE; }
extern "C" void *adr_open(const char *path, const char *password, ADRContinue proceed, void *context, int *result) {
    *result = ADR_MALFORMED;
    try {
        static const bool tablesReady = [] { CrcGenerateTable(); Sha1Prepare(); Sha256Prepare(); return true; }();
        (void)tablesReady;
        std::unique_ptr<Handle> h(new Handle);
        h->job.proceed = proceed; h->job.context = context;
        if (!h->job.Continue()) { *result = ADR_CANCELLED; return nullptr; }
        int fd = open(path, O_RDONLY|O_NOFOLLOW);
        if (fd < 0) return nullptr;
        Byte signature[8]; const ssize_t n = pread(fd, signature, 8, 0);
        if (n < 7 || memcmp(signature, "Rar!\032\007", 6) != 0) { close(fd); return nullptr; }
        h->version = signature[6] == 1 && n == 8 && signature[7] == 0 ? 5 : 4;
        h->input = new Input(fd, &h->job);
        if (h->version == 5) {
            auto *handler = new NArchive::NRar5::CHandler;
            h->archive = handler;
            const wchar_t *name = L"memx";
            CPropVariant limit((UInt64)128*1024*1024);
            if (static_cast<ISetProperties *>(handler)->SetProperties(&name, &limit, 1) != S_OK) return nullptr;
        } else { h->archive = new NArchive::NRar::CHandler; }
        CMyComPtr<IArchiveOpenCallback> callback = new OpenCallback(&h->job, password);
        UInt64 start = 0;
        HRESULT hr = h->archive->Open(h->input, &start, callback);
        *result = status(hr, h->job);
        if (*result != ADR_OK) return nullptr;
        h->encryptedHeaders = h->job.askedPassword;
        if (truth(property(h.get(), 0, kpidIsVolume, true))) { *result = ADR_UNSUPPORTED; return nullptr; }
        for (PROPID id : {kpidErrorFlags, kpidWarningFlags}) {
            auto flags = property(h.get(), 0, id, true);
            if ((flags.vt == VT_UI4 && flags.ulVal != 0) || (flags.vt == VT_UI8 && flags.uhVal.QuadPart != 0)) {
                *result = ADR_PASSWORD_OR_DAMAGE; return nullptr;
            }
        }
        if (h->archive->GetNumberOfItems(&h->count) != S_OK || h->count > 100000) { *result = ADR_CAPACITY; return nullptr; }
        *result = ADR_OK; return h.release();
    } catch (int e) { *result = e; } catch (const std::bad_alloc &) { *result = ADR_CAPACITY; } catch (...) { *result = ADR_MALFORMED; }
    return nullptr;
}
extern "C" void adr_close(void *handle) { delete (Handle *)handle; }
extern "C" uint32_t adr_count(void *handle) { return ((Handle *)handle)->count; }
extern "C" int adr_headers_encrypted(void *handle) { return ((Handle *)handle)->encryptedHeaders; }
extern "C" int adr_version(void *handle) { return ((Handle *)handle)->version; }
extern "C" int adr_entry(void *handle, uint32_t index, char *path, size_t capacity, ADREntry *entry) {
    try {
        auto *h = (Handle *)handle;
        if (!h->job.Continue()) return ADR_CANCELLED;
        if (index >= h->count) return ADR_MALFORMED;
        auto name = property(h, index, kpidPath);
        if (name.vt != VT_BSTR) return ADR_MALFORMED;
        const UINT length = SysStringLen(name.bstrVal);
        if (length == 0 || length >= 4096) return ADR_MALFORMED;
        for (UINT i = 0; i < length; ++i) if (name.bstrVal[i] == 0) return ADR_MALFORMED;
        AString utf8; ConvertUnicodeToUTF8(name.bstrVal, utf8);
        if (utf8.Len() >= capacity || utf8.Len() == 0) return ADR_MALFORMED;
        memcpy(path, utf8.Ptr(), utf8.Len()+1);
        memset(entry, 0, sizeof(*entry));
        auto size = property(h, index, kpidSize);
        if (size.vt == VT_UI8) entry->size = size.uhVal.QuadPart;
        else if (size.vt != VT_EMPTY) return ADR_MALFORMED;
        auto packed = property(h, index, kpidPackSize);
        if (packed.vt == VT_UI8) entry->packed = packed.uhVal.QuadPart;
        entry->directory = truth(property(h, index, kpidIsDir));
        entry->encrypted = truth(property(h, index, kpidEncrypted));
        entry->unsafe = truth(property(h, index, kpidIsAltStream));
        for (PROPID id : {kpidSymLink, kpidHardLink}) {
            auto link = property(h, index, id);
            if (link.vt == VT_BSTR && SysStringLen(link.bstrVal)) entry->unsafe = 1;
        }
        auto attr = property(h, index, kpidAttrib);
        if (attr.vt == VT_UI4 && (attr.ulVal & 0x8000)) {
            unsigned type = (attr.ulVal >> 16) & S_IFMT;
            if (type && type != S_IFREG && type != S_IFDIR) entry->unsafe = 1;
        }
        auto crc = property(h, index, kpidCRC);
        if (crc.vt == VT_UI4) { entry->crc = crc.ulVal; entry->has_crc = 1; }
        return ADR_OK;
    } catch (int e) { return e; } catch (const std::bad_alloc &) { return ADR_CAPACITY; } catch (...) { return ADR_MALFORMED; }
}
extern "C" int adr_extract(void *handle, uint32_t index, uint64_t expected_size, const char *password, ADRWrite write, void *context) {
    try {
        auto *h = (Handle *)handle;
        if (index >= h->count) return ADR_MALFORMED;
        h->job.missingPassword = false;
        Output *output = new Output;
        CMyComPtr<ISequentialOutStream> outputRef = output;
        output->job = &h->job; output->write = write; output->context = context; output->expected = expected_size;
        ExtractCallback *callback = new ExtractCallback;
        CMyComPtr<IArchiveExtractCallback> callbackRef = callback;
        callback->job = &h->job; callback->password = password; callback->index = index; callback->output = outputRef;
        HRESULT hr = h->archive->Extract(&index, 1, 0, callbackRef);
        int result = status(hr, h->job);
        if (result) return result;
        if (callback->error) return callback->error;
        if (!callback->targetSeen || output->actual != expected_size) return ADR_PASSWORD_OR_DAMAGE;
        return ADR_OK;
    } catch (const std::bad_alloc &) { return ADR_CAPACITY; } catch (...) { return ADR_MALFORMED; }
}
