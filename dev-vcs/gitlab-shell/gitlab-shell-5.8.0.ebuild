# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

EAPI="6"

USE_RUBY="ruby23"

inherit eutils ruby-ng user

MY_PV="v${PV/_/-}"
MY_GIT_COMMIT="1e587d3b7fbe596ab010cb022b0c6526d2489613"

DESCRIPTION="SSH access and repository management for GitLab"
HOMEPAGE="https://gitlab.com/gitlab-org/gitlab-shell"
SRC_URI="https://gitlab.com/gitlab-org/gitlab-shell/repository/archive.tar.gz?ref=${MY_PV} -> ${P}.tar.gz"
RUBY_S="${PN}-${MY_PV}-${MY_GIT_COMMIT}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~x86 ~arm ~arm64"
IUSE=""

CDEPEND=">=dev-lang/go-1.8.3"
DEPEND=""
RDEPEND="
	>=dev-vcs/git-2.7.4
	dev-db/redis
	virtual/ssh"
ruby_add_bdepend "
	virtual/ruby-ssl"

MERGE_TYPE="binary"

RUBY_PATCHES=(
	"0001-${PN}-4.1.1-config-paths.patch"
	"0002-${PN}-5.1.1-Makefile.patch"
)

RESTRICT="mirror"

GIT_USER="git"
DEST_DIR="/usr/share/${PN}"
DATA_DIR="/var/lib/git"
LOGS_DIR="/var/log/gitlab"
CONF_FILE="/etc/gitlab-shell.yml"

pkg_setup() {
	enewgroup ${GIT_USER}
	enewuser ${GIT_USER} -1 /bin/bash ${DATA_DIR} "${GIT_USER}"

	local git_shell=$(egetshell ${GIT_USER})
	if [ ! ${git_shell} -ef '/bin/bash' ]; then
		ewarn "User ${GIT_USER} already exists, but with the shell ${git_shell}."
		ewarn "Changing shell to /bin/bash ..."

		usermod -s /bin/bash ${GIT_USER} \
			|| die "failed to change login shell for ${GIT_USER}"
	fi
}

all_ruby_prepare() {
	# fix paths
	sed -i -E \
		-e "s|/home/git|${DATA_DIR}|" \
		-e "s|[\# ]*(log_file: ).*|\1\"${LOGS_DIR}/gitlab-shell.log\"|" \
		config.yml.example || die "failed to filter config.yml.example"

	sed -i \
		-e "s|File\.join(ROOT_PATH, 'config.yml')|'${CONF_FILE}'|" \
		lib/gitlab_config.rb || die "failed to filter gitlab_config.rb"
}

all_ruby_compile() {
	emake all
}

all_ruby_install() {
	# install lib
	insinto ${DEST_DIR}; doins -r lib LICENSE README.md VERSION

	# install scripts
	exeinto ${DEST_DIR}/bin; doexe bin/*
	exeinto ${DEST_DIR}/hooks; doexe hooks/*
	exeinto ${DEST_DIR}/support; doexe support/*

	# create symlinks to bin
	local name; for name in $(basename -a bin/gitlab-*); do
		dosym "${DEST_DIR}/bin/${name}" "/usr/bin/${name}"
	done

	insinto $(dirname ${CONF_FILE})
	newins config.yml.example $(basename ${CONF_FILE})

	# create symlink for .gitlab_shell_secret
	einfo "creating symlink for .gitlab_shell_secret"
	TOKEN_FILE="${DEST_DIR}/.gitlab_shell_secret"
	dosym /opt/gitlab/.gitlab_shell_secret "${TOKEN_FILE}"

	# Gitaly stupidly hardcodes the path to config.yml :(
	MY_CONF_FILE="${DEST_DIR}/config.yml"
	dosym "${CONF_FILE}" "${MY_CONF_FILE}"

	# prepare directories
	diropts -m750; dodir ${DATA_DIR}
	diropts -m770; keepdir ${DATA_DIR}/repositories
	diropts -m755; dodir ${LOGS_DIR}

	# GitLab stupidly expects that gitlab-shell is in home of git user...
	dosym ${DEST_DIR} ${DATA_DIR}/gitlab-shell

	# fix permissions
	fowners -R ${GIT_USER}:${GIT_USER} ${DATA_DIR} ${LOGS_DIR}
}

pkg_postinst() {
	# check git home directory
	local git_home=$(egethome ${GIT_USER})
	if [ ! "${git_home}" -ef ${DATA_DIR} ]; then
		ewarn "An authorized_keys is configured to be inside ${DATA_DIR}/.ssh,"
		ewarn "but HOME of ${GIT_USER} user is located in ${git_home}. You must"
		ewarn "either change the authorized_keys location in ${CONF_FILE},"
		ewarn "or change home directory of ${GIT_USER} user to ${DATA_DIR}"
		ewarn "and move ${git_home}/.ssh here."
		ewarn
	fi

	local auth_dir="${git_home}/.ssh"

	elog "Initializing authorized_keys file in ${auth_dir}"
	mkdir -p ${auth_dir}
	touch ${auth_dir}/authorized_keys
	chmod -R u=rwX,go=- ${auth_dir}
	chown -R ${GIT_USER}:${GIT_USER} ${auth_dir}

	elog
	elog "GitLab Shell was initialized. Repositories are located in"
	elog "${DATA_DIR}/repositories, scripts in ${DEST_DIR}/bin."
	elog "All gitlab-* scripts was symlinked to /usr/bin to be on your path."
	elog
	elog "You should change your gitlab_url in: ${CONF_FILE}."
}
