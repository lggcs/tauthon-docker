# Builder stage
FROM alpine:3.22 AS builder

ENV LANG=C.UTF-8 \
    PYTHONIOENCODING=UTF-8 \
    TAUTHON_TAG=v2.8.5 \
    TAUTHON_HASH=f950e3dcf60c515f339d7d6420ac0f73f77644f7 \
    INSTALL_PREFIX=/opt/tauthon

COPY fix_unicode_cast.patch /tmp/
# Fix for newer GCC versions, bug #185. https://github.com/naftaliharris/tauthon/issues/185

RUN apk add --no-cache \
    ca-certificates \
    bzip2-dev gcc gdbm-dev git libc-dev linux-headers make \
    ncurses-dev openssl openssl-dev readline-dev scanelf \
    sqlite-dev tcl-dev tk tk-dev zlib-dev binutils

# Build and install to alternate directory
RUN git clone --branch $TAUTHON_TAG https://github.com/naftaliharris/tauthon.git /tauthon \
 && cd /tauthon \
 && git apply /tmp/fix_unicode_cast.patch \
 && test "$TAUTHON_HASH" = "$(git rev-parse HEAD)" \
 && ./configure --prefix=$INSTALL_PREFIX --enable-shared --enable-unicode=ucs4 \
 && make -j$(nproc) \
 && make install

ENV LD_LIBRARY_PATH=$INSTALL_PREFIX/lib

# Install pip and virtualenv (Disabled due to multiple CVE)
#RUN $INSTALL_PREFIX/bin/tauthon -m ensurepip \
#&& $INSTALL_PREFIX/bin/tauthon -m pip install --no-cache-dir virtualenv

# Strip binaries and collect runtime files
RUN strip --strip-unneeded $INSTALL_PREFIX/bin/tauthon \
 && find $INSTALL_PREFIX -type f -name '*.so*' -exec strip --strip-unneeded {} + || true \
 \
 && mkdir -p /tauthon-runtime/opt \
 && cp -a $INSTALL_PREFIX /tauthon-runtime/opt/tauthon \
 \
 && mkdir -p /tauthon-runtime/lib \
 && ldd $INSTALL_PREFIX/bin/tauthon \
      | awk '{ print $3 }' \
      | sort -u \
      | xargs -I '{}' cp -v '{}' /tauthon-runtime/lib/ \
 \
 # copy libraries required by the tauthon binary and by Python extension modules
 && mkdir -p /tauthon-runtime/lib \
 # libs directly referenced by the tauthon executable
 && ldd $INSTALL_PREFIX/bin/tauthon \
   | awk '{ print $3 }' \
   | sort -u \
   | xargs -r -I '{}' cp -v '{}' /tauthon-runtime/lib/ || true \
 # libs referenced by Python extension modules (lib-dynload)
 && find $INSTALL_PREFIX/lib -path '*/lib-dynload/*.so' -print0 \
   | xargs -0 -n1 ldd \
   | awk '{ print $3 }' \
   | sort -u \
   | xargs -r -I '{}' cp -v '{}' /tauthon-runtime/lib/ || true \
# Copy Tcl/Tk runtime files
 && cp -a /usr/lib/tcl8.6 /tauthon-runtime/lib/ \
 && cp -a /usr/lib/tk8.6 /tauthon-runtime/lib/ \
 && mkdir -p /tauthon-runtime/etc/ssl/certs \
 && cp -v /etc/ssl/certs/ca-certificates.crt /tauthon-runtime/etc/ssl/certs/

# Add static passwd/group files for non-root user (UID/GID 1000)
RUN mkdir -p /tauthon-runtime/etc \
 && echo 'tauthon:x:1000:1000::/home/tauthon:/bin/sh' > /tauthon-runtime/etc/passwd \
 && echo 'tauthon:x:1000:' > /tauthon-runtime/etc/group \
 && mkdir -p /tauthon-runtime/home/tauthon \
 && chown 1000:1000 /tauthon-runtime/home/tauthon

# Final scratch image
FROM scratch

COPY --from=builder /tauthon-runtime/ /

ENV LANG=C.UTF-8 \
    PYTHONIOENCODING=UTF-8 \
    PATH="/opt/tauthon/bin" \
    TCL_LIBRARY="/lib/tcl8.6" \
    TK_LIBRARY="/lib/tk8.6"


USER 1000:1000
WORKDIR /home/tauthon

CMD ["/opt/tauthon/bin/tauthon2"]
