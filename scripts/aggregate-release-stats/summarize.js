const fs = require('fs');
const process = require('process');

if (process.argv.length < 2) {
    console.log(`Usage ${process.argv[0]} ${process.argv[1]} <pre-terminate-stats-directory>`);
    process.exit(1);
}

const dir = process.argv[2];

const colibri = JSON.parse(fs.readFileSync(`${dir}/colibri-stats.json`));
const conferencePacketStats = JSON.parse(fs.readFileSync(`${dir}/conference-packet-stats.json`));
const ice = JSON.parse(fs.readFileSync(`${dir}/ice-stats.json`));
const metrics = JSON.parse(fs.readFileSync(`${dir}/metrics.json`));
const node = JSON.parse(fs.readFileSync(`${dir}/node-stats.json`));
const queue = JSON.parse(fs.readFileSync(`${dir}/queue-stats.json`));
const transit = JSON.parse(fs.readFileSync(`${dir}/transit-stats.json`))['e2e_packet_delay'];


const endpoints = metrics.endpoints_total;
const visitors = metrics.visitors_total;
const relays = metrics.relays_total;
const conferences = metrics.conferences_created_total;
const seconds = colibri.total_conference_seconds;
const years = seconds / (60 * 60 * 24 * 365);
const minutesAvg = seconds / (conferences * 60);
const videoStreamSeconds = colibri.total_video_stream_milliseconds_received / 1000;
const videoStreamYears = videoStreamSeconds / (60 * 60 * 24 * 365);

console.log(`Conferences total:\t${conferences}`);
console.log(`Endpoints total:\t${endpoints}`);
console.log(`Visitors total:\t${visitors}`);
console.log(`Visitors:\t${100 * visitors / endpoints}%`);
console.log(`Relays total:\t${relays}`);
console.log(``);
console.log(`Average conference size:\t${endpoints / conferences}`);
console.log(`Total conference duration:\t${years} years`);
console.log(`Average conference duration:\t${minutesAvg} minutes`);
console.log(`Total video stream received duration:\t${videoStreamYears} years`);
console.log(``);

const tbRecv = colibri.total_bytes_received / 1e12;
const tbRecvOcto = colibri.total_bytes_received_octo / 1e12;
const tbSent = colibri.total_bytes_sent / 1e12;
const tbSentOcto = colibri.total_bytes_sent_octo / 1e12;
const percentBytesInSize2 = 100 * conferencePacketStats.bytes[2] / conferencePacketStats.total_bytes;
console.log(`Traffic total:\t${tbRecv + tbRecvOcto + tbSent + tbSentOcto} terabytes`);
console.log(`Octo traffic total:\t${tbRecvOcto + tbSentOcto} terabytes`);
console.log(`Octo traffic:\t${100 * (tbRecvOcto + tbSentOcto) / (tbRecv + tbRecvOcto + tbSent + tbSentOcto)}% `);
console.log(`Traffic in conferences of size 2:\t${percentBytesInSize2}%`);
console.log(``);


const messagesWs = metrics.colibri_web_socket_messages_received_total + metrics.colibri_web_socket_messages_sent_total;
const messagesSctp = metrics.data_channel_messages_received_total + metrics.data_channel_messages_sent_total;
const messages = messagesWs + messagesSctp;
console.log(`Average bridge channel messages per endpoint:\t${messages / endpoints}`);
console.log(`Bridge channel messages SCTP:\t${100 * messagesSctp / messages}%`);
console.log(`Bridge channel messages WS:\t${100 * messagesWs / messages}%`);
const dsChanges = metrics.dominant_speaker_changes_total;
console.log(`Average time between dominant speaker changes:\t${seconds / dsChanges} seconds`);
console.log(``);

const iceFailed = metrics.ice_failed_total;
const dtlsFailed = metrics.endpoints_dtls_failed_total;
const iceRelay = metrics.ice_succeeded_relayed_total;
const bridgeChannelFailed = metrics.endpoints_no_message_transport_after_delay_total;
const relayBridgeChannelFailed = metrics.relays_no_message_transport_after_delay_total;
const failedConferences = metrics.partially_failed_conferences_total + metrics.failed_conferences_total;
console.log(`ICE failures total:\t${iceFailed}`);
console.log(`ICE failures:\t${100 * iceFailed / endpoints}%`);
console.log(`ICE used relay total:\t${iceRelay}`);
console.log(`ICE used relay:\t${100 * iceRelay / endpoints}%`);
console.log(`DTLS failures total:\t${dtlsFailed}`);
console.log(`DTLS failures:\t${100 * dtlsFailed / endpoints}%`);
console.log(`Bridge channel failures total:\t${bridgeChannelFailed}`);
console.log(`Bridge channel failures:\t${100 * bridgeChannelFailed / endpoints}%`);
console.log(`Relay bridge channel failures total:\t${relayBridgeChannelFailed}`);
console.log(`Relay bridge channel failures:\t${100 * relayBridgeChannelFailed / relays}%`);
console.log(`Conferences with ICE failures total:\t${failedConferences}`);
console.log(`Conferences with ICE failures:\t${100 * failedConferences / conferences}%`);
console.log(``);

const endpointsWithSpuriousRemb = colibri.endpoints_with_spurious_remb;
const pkfrSent = metrics.preemptive_keyframe_requests_sent_total;
const pkfrSuppressed = metrics.preemptive_keyframe_requests_suppressed_total;
const bweSecondsTotal = colibri.total_loss_controlled_participant_seconds;
const bweSecondsDegraded = colibri.total_loss_degraded_participant_seconds;
const bweSecondsLimited = colibri.total_loss_limited_participant_seconds;
const keyframes = metrics.keyframes_received_total;
const layeringChanges = metrics.layering_changes_received_total;
console.log(`Suppressed preemptive keyframe requests:\t${100 * pkfrSuppressed / (pkfrSent + pkfrSuppressed)}%`);
console.log(`Endpoints with spurious REMB:\t${100 * endpointsWithSpuriousRemb / endpoints}%`);
console.log(`BWE time "degraded":\t${100 * bweSecondsDegraded / bweSecondsTotal}%`);
console.log(`BWE time "limited":\t${100 * bweSecondsLimited / bweSecondsTotal}%`);
console.log(`Average time between keyframes:\t${videoStreamSeconds / keyframes} seconds`);
console.log(`Average time between layering changes:\t${videoStreamSeconds / layeringChanges} seconds`);
// These might also be useful, but I don't know how to interpret them in a good way:
// metrics.endpoints_disconnected_total 
// metrics.endpoints_reconnected_total
console.log(``);

console.log(`RTT [0, 10) ms:\t${100 * ice.all.buckets.buckets['0_to_10'] / ice.all.buckets.total_count}%`)
console.log(`RTT [10, 20):\t${100 * ice.all.buckets.buckets['10_to_20'] / ice.all.buckets.total_count}%`)
console.log(`RTT [20, 40):\t${100 * ice.all.buckets.buckets['20_to_40'] / ice.all.buckets.total_count}%`)
console.log(`RTT [40, 60):\t${100 * ice.all.buckets.buckets['40_to_60'] / ice.all.buckets.total_count}%`)
console.log(`RTT [60, 80):\t${100 * ice.all.buckets.buckets['60_to_80'] / ice.all.buckets.total_count}%`)
console.log(`RTT [80, 100):\t${100 * ice.all.buckets.buckets['80_to_100'] / ice.all.buckets.total_count}%`)
console.log(`RTT [100, 150):\t${100 * ice.all.buckets.buckets['100_to_150'] / ice.all.buckets.total_count}%`)
console.log(`RTT [150, 200):\t${100 * ice.all.buckets.buckets['150_to_200'] / ice.all.buckets.total_count}%`)
console.log(`RTT [200, 250):\t${100 * ice.all.buckets.buckets['200_to_250'] / ice.all.buckets.total_count}%`)
console.log(`RTT [250, 300):\t${100 * ice.all.buckets.buckets['250_to_300'] / ice.all.buckets.total_count}%`)
console.log(`RTT [300, 500):\t${100 * ice.all.buckets.buckets['300_to_500'] / ice.all.buckets.total_count}%`)
console.log(`RTT [500, 1000):\t${100 * ice.all.buckets.buckets['500_to_1000'] / ice.all.buckets.total_count}%`)
console.log(`RTT [1000, max):\t${100 * ice.all.buckets.buckets['1000_to_max'] / ice.all.buckets.total_count}%`)
console.log(``);

console.log(`Packets dropped in bridge-channel-message-incoming-queue:\t${queue['bridge-channel-message-incoming-queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in colibri_queue:\t${queue['colibri_queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in relay_endpoint_sender_srtp_send_queue:\t${queue['relay_endpoint_sender_srtp_send_queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in relay_srtp_send_queue:\t${queue['relay_srtp_send_queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in rtp_receiver_queue:\t${queue['rtp_receiver_queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in rtp_sender_queue:\t${queue['rtp_sender_queue']['queue_size_at_remove'].discarded}`);
console.log(`Packets dropped in srtp_send_queue:\t${queue['srtp_send_queue']['queue_size_at_remove'].discarded}`);
console.log(``);

console.log(`RTP packets discarded:\t${transit.rtp.discarded}`);
console.log(`RTP packets delayed > 500ms:\t1 out of ${transit.rtp['total_count'] / transit.rtp.buckets['500_to_max_ms']}`)
console.log(`RTP packets delayed > 50ms:\t1 out of ${transit.rtp['total_count'] / transit.rtp.buckets['50_to_max_ms']}`)
console.log(`RTCP packets discarded:\t${transit.rtcp.discarded}`);
console.log(`RCTP packets delayed > 500ms:\t1 out of ${transit.rtcp['total_count'] / transit.rtcp.buckets['500_to_max_ms']}`)
console.log(`RCTP packets delayed > 50ms:\t1 out of ${transit.rtcp['total_count'] / transit.rtcp.buckets['50_to_max_ms']}`)
console.log(``);

const mediaType = node['Media Type demuxer'];
console.log(`Audio packets received:\t${100 * mediaType['packets_accepted_Audio path'] / mediaType['num_output_packets']}%`);
console.log(`Video packets received:\t${100 * mediaType['packets_accepted_Video path'] / mediaType['num_output_packets']}%`);

const audioLevels = node['AudioLevelReader$AudioLevelReaderNode'];
console.log(`Audio packets discarded due to force-mute:\t${100 * audioLevels['num_force_mute_discarded'] / audioLevels['num_audio_levels']}%`);
console.log(`Audio packets discarded due to ranking:\t${100 * audioLevels['num_ranking_discarded'] / audioLevels['num_audio_levels']}%`);
console.log(`Audio packets discarded due to silence:\t${100 * audioLevels['num_silence_packets_discarded'] / audioLevels['num_audio_levels']}%`);
console.log(`Audio packets non-silence:\t${100 * audioLevels['num_non_silence'] / audioLevels['num_audio_levels']}%`);
console.log(`Audio packets non-silence with VAD:\t${100 * audioLevels['num_non_silence_with_vad'] / audioLevels['num_audio_levels']}%`);

const videoMute = node['VideoMuteNode'];
console.log(`Video packets discarded due to force-mute:\t${100 * videoMute['num_video_packets_discarded'] / videoMute['num_input_packets']}%`);

// This could be useful when RED is enabled.
const audioRed = node['AudioRedHandler'];

const duplicate = node['DuplicateTermination'];
console.log(`Duplicate packets discarded (probing?):\t${100 * duplicate['num_duplicate_packets_dropped'] / duplicate['num_input_packets']}%`);

const kfr = node['KeyframeRequester'];
console.log(`KeyframeRequester API requests dropped:\t${100 * kfr['num_api_requests_dropped'] / kfr['num_api_requests']}%`);


const sent = node['OutgoingStatisticsTracker'];
console.log(`Audio packets sent:\t${100 * sent['num_audio_packets'] / sent['num_output_packets']}%`);
console.log(`Video packets sent:\t${100 * sent['num_video_packets'] / sent['num_output_packets']}%`);

const cache = node['PacketCacher']['PacketCache'];
console.log(`Packet cache hits:\t${100 * cache.numHits / cache.numRequests}%`);
console.log(`Packet cache misses:\t${100 * cache.numMisses / cache.numRequests}%`);
console.log(`Packet cache old inserts:\t${100 * cache.numOldInserts / cache.numInserts}%`);

const padding = node['PaddingTermination'];
console.log(`Packets with padding:\t${100 * padding['num_padded_packets_seen'] / padding['num_output_packets']}%`);
console.log(`Packets with only padding:\t${100 * padding['num_padding_only_packets_seen'] / padding['num_output_packets']}%`);

const retransmissions = node['RetransmissionSender'];
console.log(`Retransmissions sent plain:\t${100 * retransmissions['num_retransmissions_plain_sent'] / retransmissions['num_retransmissions_requested']}%`);
console.log(`Retransmissions sent with RTX:\t${100 * retransmissions['num_retransmissions_rtx_sent'] / retransmissions['num_retransmissions_requested']}%`);

const rtcp = node['RtcpTermination'];
const rtcp_bye = rtcp['num_RtcpByePacket_rx'];
const rtcp_nack = rtcp['num_RtcpFbNackPacket_rx'];
const rtcp_pli = rtcp['num_RtcpFbPliPacket_rx'];
const rtcp_remb = rtcp['num_RtcpFbRembPacket_rx'];
const rtcp_tcc = rtcp['num_RtcpFbTccPacket_rx'];
const rtcp_rr = rtcp['num_RtcpRrPacket_rx'];
const rtcp_sdes = rtcp['num_RtcpSdesPacket_rx'];
const rtcp_sr = rtcp['num_RtcpSrPacket_rx'];
const rtcp_xr = rtcp['num_RtcpXrPacket_rx'];
const rtcp_all = rtcp_bye + rtcp_nack + rtcp_pli + rtcp_remb + rtcp_tcc + rtcp_rr + rtcp_sdes + rtcp_sr + rtcp_xr;
console.log(`RTCP received BYE:\t${100 * rtcp_bye / rtcp_all}%`);
console.log(`RTCP received NACK:\t${100 * rtcp_nack / rtcp_all}%`);
console.log(`RTCP received PLI:\t${100 * rtcp_pli / rtcp_all}%`);
console.log(`RTCP received REMB:\t${100 * rtcp_remb / rtcp_all}%`);
console.log(`RTCP received TCC:\t${100 * rtcp_tcc / rtcp_all}%`);
console.log(`RTCP received RR:\t${100 * rtcp_rr / rtcp_all}%`);
console.log(`RTCP received SDES:\t${100 * rtcp_sdes / rtcp_all}%`);
console.log(`RTCP received SR:\t${100 * rtcp_sr / rtcp_all}%`);
console.log(`RTCP received XR:\t${100 * rtcp_xr / rtcp_all}%`);

const rtpParser = node['RtpParser'];
console.log(`RTP parser discarded packets:\t${100 * rtpParser['num_discarded_packets'] / rtpParser['num_input_packets']}%`);

const rtx = node['RtxHandler'];
console.log(`RTX packets received:\t${100 * rtx['num_rtx_packets_received'] / rtx['num_input_packets']}%`);

const rtcpDemux = node['SRTP/SRTCP demuxer'];
console.log(`RTCP packets received:\t${100 * rtcpDemux['packets_accepted_SRTCP path'] / rtcpDemux['num_input_packets']}%`);

const rtcp_sent = node['SentRtcpStats'];
const rtcp_sent_compound = rtcp_sent['num_CompoundRtcpPacket_tx'];
const rtcp_sent_nack = rtcp_sent['num_RtcpFbNackPacket_tx'];
const rtcp_sent_pli = rtcp_sent['num_RtcpFbPliPacket_tx'];
const rtcp_sent_remb = rtcp_sent['num_RtcpFbRembPacket_tx'];
const rtcp_sent_tcc = rtcp_sent['num_RtcpFbTccPacket_tx'];
const rtcp_sent_rr = rtcp_sent['num_RtcpRrPacket_tx'];
const rtcp_sent_sr = rtcp_sent['num_RtcpSrPacket_tx'];
const rtcp_sent_all = rtcp_sent_compound + rtcp_sent_nack + rtcp_sent_pli + rtcp_sent_remb + rtcp_sent_tcc + rtcp_sent_rr + rtcp_sent_sr;
console.log(`RTCP sent compound:\t${100 * rtcp_sent_compound / rtcp_sent_all}%`);
console.log(`RTCP sent NACK:\t${100 * rtcp_sent_nack / rtcp_sent_all}%`);
console.log(`RTCP sent PLI:\t${100 * rtcp_sent_pli / rtcp_sent_all}%`);
console.log(`RTCP sent REMB:\t${100 * rtcp_sent_remb / rtcp_sent_all}%`);
console.log(`RTCP sent TCC:\t${100 * rtcp_sent_tcc / rtcp_sent_all}%`);
console.log(`RTCP sent RR:\t${100 * rtcp_sent_rr / rtcp_sent_all}%`);
console.log(`RTCP sent SR:\t${100 * rtcp_sent_sr / rtcp_sent_all}%`);

const srtcpDe = node['SrtcpDecryptNode'];
const srtcpEn = node['SrtcpEncryptNode'];
const srtpDe = node['SrtpDecryptNode'];
const srtpEn = node['SrtpEncryptNode'];

console.log(`SRTP/SRTCP auth_fail total:\t${srtcpDe['num_srtp_auth_fail'] + srtpDe['num_srtp_auth_fail']}`);
console.log(`SRTP/SRTCP auth_fail:\t${100 * (srtcpDe['num_srtp_auth_fail'] + srtpDe['num_srtp_auth_fail']) / (srtcpDe['num_input_packets'] + srtpDe['num_input_packets'])}%`);
console.log(`SRTP/SRTCP srtp_fail total:\t${srtcpDe['num_srtp_fail'] + srtpDe['num_srtp_fail']}`);
console.log(`SRTP/SRTCP srtp_fail:\t${100 * (srtcpDe['num_srtp_fail'] + srtpDe['num_srtp_fail']) / (srtcpDe['num_input_packets'] + srtpDe['num_input_packets'])}%`);
console.log(`SRTP/SRTCP invalid_packet total:\t${srtcpDe['num_srtp_invalid_packet'] + srtpDe['num_srtp_invalid_packet']}`);
console.log(`SRTP/SRTCP invalid_packet:\t${100 * (srtcpDe['num_srtp_invalid_packet'] + srtpDe['num_srtp_invalid_packet']) / (srtcpDe['num_input_packets'] + srtpDe['num_input_packets'])}%`);
console.log(`SRTP/SRTCP replay_fail total:\t${srtcpDe['num_srtp_replay_fail'] + srtpDe['num_srtp_replay_fail']}`);
console.log(`SRTP/SRTCP replay_fail:\t${100 * (srtcpDe['num_srtp_replay_fail'] + srtpDe['num_srtp_replay_fail']) / (srtcpDe['num_input_packets'] + srtpDe['num_input_packets'])}%`);
console.log(`SRTP/SRTCP replay_old total:\t${srtcpDe['num_srtp_replay_old'] + srtpDe['num_srtp_replay_old']}`);
console.log(`SRTP/SRTCP replay_old:\t${100 * (srtcpDe['num_srtp_replay_old'] + srtpDe['num_srtp_replay_old']) / (srtcpDe['num_input_packets'] + srtpDe['num_input_packets'])}%`);


const tccGen = node['TccGeneratorNode'];
console.log(`TCC feedback required multiple TCC packets:\t${100 * tccGen['num_multiple_tcc_packets'] / tccGen['num_tcc_packets_sent']}%`);

const vq = node['VideoQualityLayerLookup'];
console.log(`Packets dropped_no_encoding:\t${100 * vq['num_packets_dropped_no_encoding'] / vq['num_input_packets']}%`)
