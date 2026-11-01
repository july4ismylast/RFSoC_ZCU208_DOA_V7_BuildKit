# Model Composer / System Generator channelizer route

This is an alternative to `ip/matlab/channelizer_hdl`, not another datapath
copy. Set a tested model's System Generator token to **IP Catalog**, then run:

```bash
make step05_channelizer CHANNELIZER_FLOW=model_composer \
  MODEL_COMPOSER_MODEL=/absolute/path/channelizer.slx
```

The exporter updates the model, invokes the token, locates the generated
`component.xml`, and copies the IP into the common repository. Rebuild the
model with exactly the Vivado release used by `BASE_XPR`.

