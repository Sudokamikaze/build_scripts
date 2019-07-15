%global debug_package %{nil}

Summary:        Reliable PostgreSQL Backup & Restore
Name:           pgbackrest
Version:        %{version}
Release:        1%{dist}
License:        MIT
Group:          Applications/Databases
URL:            http://www.pgbackrest.org
Source:         %{name}-%{version}.tar.gz
Source1:        pgbackrest.conf
BuildRequires:  libxml2-devel
BuildRequires:  openssl-devel
BuildRequires:  perl
BuildRequires:  perl-libxml-perl
BuildRequires:  perl(DBD::Pg)
BuildRequires:  perl(Digest::SHA)
BuildRequires:  perl(IO::Socket::SSL)
BuildRequires:  perl(JSON::PP)
Requires:       perl-libxml-perl
Requires:       perl(DBD::Pg)
Requires:       perl(Digest::SHA)
Requires:       perl(IO::Socket::SSL)
Requires:       perl(JSON::PP)

%description
pgBackRest aims to be a simple, reliable backup and restore system that can
seamlessly scale up to the largest databases and workloads.

Instead of relying on traditional backup tools like tar and rsync, pgBackRest
implements all backup features internally and uses a custom protocol for
communicating with remote systems. Removing reliance on tar and rsync allows
for better solutions to database-specific backup challenges. The custom remote
protocol allows for more flexibility and limits the types of connections that
are required to perform a backup which increases security.

%prep
%setup -q -n %{name}-%{version}

%build
pushd src
%configure
%{__make}
popd

%install
%{__install} -D -d -m 0755 %{buildroot}%{perl_vendorlib} %{buildroot}%{_bindir}
%{__install} -D -d -m 0700 %{buildroot}/%{_sharedstatedir}/%{name}
%{__install} -D -d -m 0700 %{buildroot}/var/log/%{name}
%{__install} -D -d -m 0700 %{buildroot}/var/spool/%{name}
%{__install} -D -d -m 0755 %{buildroot}%{_sysconfdir}
%{__install} %{SOURCE1} %{buildroot}/%{_sysconfdir}/%{name}.conf
%{__cp} -a src/%{name} %{buildroot}%{_bindir}/%{name}

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-,root,root)
%if 0%{?rhel} && 0%{?rhel} <= 6
%doc LICENSE
%else
%license LICENSE
%endif
%{_bindir}/%{name}
%config(noreplace) %attr (644,root,root) %{_sysconfdir}/%{name}.conf
%attr(-,postgres,postgres) /var/log/%{name}
%attr(-,postgres,postgres) %{_sharedstatedir}/%{name}
%attr(-,postgres,postgres) /var/spool/%{name}

%changelog
* Tue Jul 16 2019  Evgeniy Patlan <evgeniy.patlan@percona.com> - 2.15.1
- First build of pgbackrest for Percona.
