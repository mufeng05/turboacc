/* Copyright (C) 2022 ImmortalWrt.org */

'use strict';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';

var getSystemFeatures = rpc.declare({
	object: 'luci.turboacc',
	method: 'getSystemFeatures',
	expect: { '': {} }
});

return view.extend({
	getRuntimeStatus() {
		return L.resolveDefault(
			fs.exec_direct('/usr/libexec/luci-turboacc-status', [], 'json'), {});
	},

	load() {
		return Promise.all([
			L.resolveDefault(getSystemFeatures(), {}),
			this.getRuntimeStatus()
		]);
	},

	render([features, runtimeStatus]) {
		let m, s, o;
		const fw4 = L.hasSystemFeature('firewall4');
		const runtimeStatusText = E('span', {}, [ '-' ]);
		const updateRuntimeStatus = (status) => {
			const natModes = {
				fullcone: 'FULLCONENAT',
				nat1: _('Broadcom Fullcone NAT1'),
				disabled: _('Disabled')
			};
			const natMode = natModes[status?.nat_mode] || _('Unknown');
			const tcpcca = status?.tcp_cca
				? status.tcp_cca.toUpperCase()
				: _('Unknown');

			runtimeStatusText.textContent =
				_('Running status: %s, TCP congestion control algorithm is %s').format(natMode, tcpcca);
		};
		const addTCPCCAOption = () => {
			const tcpcca = s.option(form.ListValue, 'tcpcca', _('TCP CCA'),
				_('TCP congestion control algorithm.'));
			tcpcca.value('bbr', 'bbr');
			tcpcca.value('cubic', 'cubic');
			tcpcca.value('reno', 'reno');
			tcpcca.default = 'cubic';
			tcpcca.rmempty = false;
		};
		/* The Shortcut-FE options are kept in the turboacc config */
		const turboaccOption = (opt) => {
			opt.load = () => uci.get('turboacc', 'config', opt.option);
			opt.write = (section_id, value) => {
				if (!uci.get('turboacc', 'config'))
					uci.add('turboacc', 'turboacc', 'config');
				uci.set('turboacc', 'config', opt.option, value);
			};
			opt.remove = () => uci.unset('turboacc', 'config', opt.option);
			return opt;
		};

		updateRuntimeStatus(runtimeStatus);

		m = new form.Map('firewall', _('TurboACC settings'),
			_('Open source flow offloading engine (fast path or hardware NAT).'));
		m.chain('turboacc');
		const hasQualcommECM = runtimeStatus?.ecm_available === true;
		if (hasQualcommECM)
			m.chain('ecm');

		/* With a context, as the official luci-base translates "General Settings" differently from lede */
		s = m.section(form.TypedSection, 'defaults', _('General Settings', 'TurboACC'));
		s.anonymous = true;
		s.addremove = false;

		if (features.hasXTFULLCONENAT || features.hasNFTFULLCONENAT) {
			o = s.option(form.ListValue, 'fullcone', _('Enable FullCone NAT'));
			o.value('0', _('Disable'));
			o.value('1', _('FULLCONENAT'));
			o.value('2', _('Broadcom Fullcone NAT1'));
			addTCPCCAOption();
			if (fw4)
				o = s.option(form.Flag, 'fullcone6', _('Enable FullCone NAT6'));
		}
		else {
			addTCPCCAOption();
		}

		/* Netfilter flow offload support */

		const hasMediatekHNAT = fw4 && runtimeStatus?.hnat_available === true;
		const hasOffloading = L.hasSystemFeature('offloading') || hasMediatekHNAT || hasQualcommECM;
		if (hasOffloading) {
			s = m.section(form.TypedSection, 'defaults', _('Routing/NAT Offloading'),
				_('Not fully compatible with QoS/SQM.'));

			s.anonymous = true;
			s.addremove = false;

			o = s.option(form.RichListValue, "offloading_type", _("Flow offloading type"));
			o.value('0', _("None"));
			if (L.hasSystemFeature('offloading'))
				o.value('1', _("Software flow offloading"), _('Software based offloading for routing/NAT.'));
			if (features.hasHWFLOWOFFLOADING)
				o.value('2', _("Hardware flow offloading"), _('Hardware based offloading for routing with/without NAT.') + ' ' + _(' Requires hardware NAT support.'));
			if (hasMediatekHNAT)
				o.value('3', _('MediaTek HNAT'), _('Hardware NAT offloading using the MediaTek vendor driver.'));
			if (hasQualcommECM)
				o.value('4', _('Qualcomm NSS ECM acceleration'), _('Automatically select the acceleration engine in ECM Auto mode.'));
			o.optional = false;
			o.load = function (section_id) {
				const flow_offloading = uci.get('firewall', section_id, 'flow_offloading');
				const flow_offloading_hw = uci.get('firewall', section_id, 'flow_offloading_hw');
				const has_hw_offloading = features.hasHWFLOWOFFLOADING;
				if (hasQualcommECM && uci.get('ecm', 'global', 'acceleration_engine') !== 'disabled')
					return '4';
				if (hasMediatekHNAT && flow_offloading === '3')
					return '3';
				return (flow_offloading === '1' && L.hasSystemFeature('offloading'))
					? ((flow_offloading_hw === '1' && has_hw_offloading) ? '2' : '1')
					: '0';
			};
			o.write = function(section_id, value) {
				if (hasQualcommECM) {
					if (!uci.get('ecm', 'global'))
						uci.add('ecm', 'ecm', 'global');
					uci.set('ecm', 'global', 'acceleration_engine', value === '4' ? 'auto' : 'disabled');
				}
				uci.set('firewall', section_id, 'flow_offloading', value === '3' ? '3' : ((value === '1' || value === '2') ? '1' : '0'));
				uci.unset('firewall', section_id, 'mediatek_hnat');
				uci.set('firewall', section_id, 'flow_offloading_hw',
					(value === '2' && features.hasHWFLOWOFFLOADING) ? '1' : null);
			};

			if (fw4 && features.hasHWFLOWOFFLOADING) {
				o = s.option(form.ListValue, 'flow_offloading_hw_ipv6', _('Hardware offloading protocols'));
				o.value('1', _('IPv4+v6 acceleration'));
				o.value('0', _('IPv4 acceleration'));
				o.default = '1';
				o.rmempty = false;
				o.retain = true;
				o.depends('offloading_type', '2');
			}
		}

		/* Shortcut-FE */

		if (features.hasFASTCLASSIFIER || features.hasSHORTCUTFECM) {
			s = m.section(form.TypedSection, 'defaults', _('Shortcut-FE'),
				hasOffloading ? _('Cannot be used together with flow offloading, only available when the flow offloading type is None.') : null);

			s.anonymous = true;
			s.addremove = false;

			o = turboaccOption(s.option(form.RichListValue, 'fastpath', _('Fastpath engine')));
			o.value('disabled', _('Disable'));
			if (features.hasFASTCLASSIFIER)
				o.value('fast_classifier', _('Fast classifier'),
					_('Fast classifier connection manager for the shortcut forwarding engine.'));
			if (features.hasSHORTCUTFECM)
				o.value('shortcut_fe_cm', _('SFE connection manager'),
					_('Simple connection manager for the shortcut forwarding engine.'));
			o.default = 'disabled';
			o.rmempty = false;
			if (hasOffloading)
				o.depends('offloading_type', '0');

			o = turboaccOption(s.option(form.Flag, 'fastpath_fc_br', _('Bridge Acceleration'),
				_('Enable bridge acceleration (may be functional conflict with bridge-mode VPN server).')));
			o.default = o.disabled;
			o.rmempty = false;
			o.depends('fastpath', 'fast_classifier');

			if (features.hasIPV6) {
				o = turboaccOption(s.option(form.Flag, 'fastpath_fc_ipv6', _('IPv6 acceleration'),
					_('Enable IPv6 Acceleration.')));
				o.default = o.disabled;
				o.rmempty = false;
				o.depends('fastpath', 'fast_classifier');
			}
		}

		return m.render().then(L.bind(function(mapEl) {
			const firstSection = mapEl.querySelector('.cbi-section');
			const statusSection = E('div', {
				'class': 'cbi-section firewall-runtime-status',
				'style': 'overflow-x:auto'
			}, [
				E('div', {
					'style': 'padding:.75em 1.5em;color:#008000;font-size:1em;font-weight:600;white-space:nowrap'
				}, [ runtimeStatusText ])
			]);

			firstSection.parentNode.insertBefore(statusSection, firstSection);

			poll.add(L.bind(function() {
				return this.getRuntimeStatus().then(updateRuntimeStatus);
			}, this), 5);

			return mapEl;
		}, this));
	}
});
