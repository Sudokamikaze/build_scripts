%global debug_package %{nil}
%global sname   percona-pg_repack
%global pgmajorversion 11
%global pginstdir /usr/pgsql-11

Summary:        Reorganize tables in PostgreSQL databases without any locks
Name:           %{sname}%{pgmajorversion}
Version:        %{version}
Release:        2%{?dist}
Epoch:          1
License:        BSD
Group:          Applications/Databases
Source0:        %{sname}-%{version}.tar.gz
Patch0:         pg_repack-pg%{pgmajorversion}-makefile-pgxs.patch
URL:            https://pgxn.org/dist/pg_repack/
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-%(%{__id_u} -n)

BuildRequires:  percona-postgresql%{pgmajorversion}-devel, percona-postgresql%{pgmajorversion}
Requires:       postgresql%{pgmajorversion}
Provides: pg_repack

%description
pg_repack can re-organize tables on a postgres database without any locks so that
you can retrieve or update rows in tables being reorganized.
The module is developed to be a better alternative of CLUSTER and VACUUM FULL.

%prep
%setup -q -n %{sname}-%{version}
%patch0 -p0

%build
USE_PGXS=1 make %{?_smp_mflags}

%install
%{__rm} -rf %{buildroot}
USE_PGXS=1 make DESTDIR=%{buildroot} install

%post
update-alternatives --install /usr/bin/pg_repack pg_repack %{pginstdir}/bin/pg_repack 100

%postun
update-alternatives --remove pg_repack %{pginstdir}/bin/pg_repack

%files
%defattr(644,root,root)
%doc COPYRIGHT doc/pg_repack.rst
%attr (755,root,root) %{pginstdir}/bin/pg_repack
%attr (755,root,root) %{pginstdir}/lib/pg_repack.so
%{pginstdir}/share/extension/pg_repack--%{version}.sql
%{pginstdir}/share/extension/pg_repack.control
%{pginstdir}/lib/bitcode/pg_repack*.bc
%{pginstdir}/lib/bitcode/pg_repack/*.bc
%{pginstdir}/lib/bitcode/pg_repack/pgut/*.bc

%clean
%{__rm} -rf %{buildroot}

%changelog
* Tue Aug 30 2019 Evgeniy Patlan <evgeniy.patlan@percona.com> - 1.4.4-2
- Initial build
