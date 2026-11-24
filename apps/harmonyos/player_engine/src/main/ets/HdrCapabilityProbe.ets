import { display } from '@kit.ArkUI';
import { hdrCapability } from '@kit.ArkGraphics2D';

export class HdrCapabilityProbe {
  private static _hdrFormats: hdrCapability.HDRFormat[] | null = null;
  private static _hdrPassthrough: boolean | null = null;
  private static _dvProfiles: number[] | null = null;
  private static _dvBaseProfiles: number[] | null = null;

  static probe(): void {
    let formats: hdrCapability.HDRFormat[] = [];
    try {
      const disp = display.getDefaultDisplaySync();
      formats = disp.hdrFormats ?? [];
    } catch (error) {
      formats = [];
    }
    HdrCapabilityProbe._hdrFormats = formats;
    HdrCapabilityProbe._hdrPassthrough = formats.length > 0;
    const dvProfiles: number[] = [];
    const dvBaseProfiles: number[] = [];
    for (const fmt of formats) {
      if (fmt === hdrCapability.HDRFormat.VIDEO_HDR_VIVID) {
        dvProfiles.push(8);
        dvBaseProfiles.push(8);
      }
    }
    HdrCapabilityProbe._dvProfiles = dvProfiles;
    HdrCapabilityProbe._dvBaseProfiles = dvBaseProfiles;
  }

  static get hdrPassthrough(): boolean {
    if (HdrCapabilityProbe._hdrPassthrough === null) { HdrCapabilityProbe.probe(); }
    return HdrCapabilityProbe._hdrPassthrough ?? false;
  }

  static get dolbyVisionProfiles(): number[] {
    if (HdrCapabilityProbe._dvProfiles === null) { HdrCapabilityProbe.probe(); }
    return HdrCapabilityProbe._dvProfiles ?? [];
  }

  static get dolbyVisionBaseLayerProfiles(): number[] {
    if (HdrCapabilityProbe._dvBaseProfiles === null) { HdrCapabilityProbe.probe(); }
    return HdrCapabilityProbe._dvBaseProfiles ?? [];
  }

  static get hdrFormats(): hdrCapability.HDRFormat[] {
    if (HdrCapabilityProbe._hdrFormats === null) { HdrCapabilityProbe.probe(); }
    return HdrCapabilityProbe._hdrFormats ?? [];
  }

  static get supportsHdr10(): boolean {
    return HdrCapabilityProbe.hdrFormats.indexOf(hdrCapability.HDRFormat.VIDEO_HDR10) >= 0;
  }

  static get supportsHlg(): boolean {
    return HdrCapabilityProbe.hdrFormats.indexOf(hdrCapability.HDRFormat.VIDEO_HLG) >= 0;
  }

  static get supportsHdrVivid(): boolean {
    return HdrCapabilityProbe.hdrFormats.indexOf(hdrCapability.HDRFormat.VIDEO_HDR_VIVID) >= 0;
  }
}
