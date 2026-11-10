/* eslint-disable @next/next/no-img-element */
import { forwardRef } from 'react'
import type React from 'react'

type ImgFetchPriority = 'high' | 'low' | 'auto'

export type RawImageProps = Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'fetchPriority'> & {
  fetchPriority?: ImgFetchPriority
}

// Static export and runtime asset URLs make native <img> the most predictable choice here.
export const RawImage = forwardRef(function RawImage(
  props: RawImageProps,
  ref: React.ForwardedRef<HTMLImageElement>
) {
  const { alt = '', ...rest } = props
  return <img ref={ref} alt={alt} {...rest} />
})

RawImage.displayName = 'RawImage'
