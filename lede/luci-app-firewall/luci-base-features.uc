function has_supported_hw_offloading_target(target) {
	if (target == 'ipq40xx/generic')
		return access('/sys/module/qca_ssdk') == true &&
			access('/sys/module/essedma') == true;

	return type(target) == 'string' &&
		match(target, /^(ramips\/mt7621|mediatek\/mt76..|mediatek\/filogic|airoha\/an758[0-9])$/) != null;
}
			const has_fw3 = access('/sbin/fw3') == true;
			const has_fw4 = access('/sbin/fw4') == true || access('/usr/sbin/fw4') == true;
			const has_ipt_flowoffload = access('/sys/module/xt_FLOWOFFLOAD/refcnt') == true;
			const has_nft_flowoffload = access('/sys/module/nft_flow_offload/refcnt') == true;
			const has_mt7621_vendor_hnat = sysboard?.release?.target == 'ramips/mt7621' &&
				access('/sys/module/mtkhnat') == true;
			const has_hw_offloading = !has_mt7621_vendor_hnat &&
				has_supported_hw_offloading_target(sysboard?.release?.target) &&
				((has_fw3 && has_ipt_flowoffload) || (has_fw4 && has_nft_flowoffload));
				offloading: (has_fw3 && has_ipt_flowoffload) || (has_fw4 && has_nft_flowoffload),
				offloading_hw: has_hw_offloading,
				fullcone:   access('/sys/module/xt_FULLCONENAT/refcnt') == true || access('/sys/module/nft_fullcone/refcnt') == true,
