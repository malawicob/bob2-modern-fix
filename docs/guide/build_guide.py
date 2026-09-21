import base64, io, sys
from PIL import Image
S=sys.argv[1]; R='/home/patrick_millin/bob2/BOB2-Win11-Fix'
def uri(path, w=1100, crop_h=None, q=80, bg=(16,24,30)):
    im=Image.open(path)
    if im.mode in ('RGBA','LA'):
        b=Image.new('RGB',im.size,bg); b.paste(im,(0,0),im.convert('RGBA')); im=b
    im=im.convert('RGB')
    if crop_h and im.size[1]>crop_h: im=im.crop((0,0,im.size[0],crop_h))
    if im.size[0]>w: im=im.resize((w,int(im.size[1]*w/im.size[0])),Image.LANCZOS)
    o=io.BytesIO(); im.save(o,'JPEG',quality=q,optimize=True)
    return 'data:image/jpeg;base64,'+base64.b64encode(o.getvalue()).decode()
img={
 'hero': uri(R+'/docs/showcase-09-qj-spitfire.png',1024),
 'raf': uri(S+'/shots/raf-dispersal.png',1100,1020),
 'lw': uri(S+'/shots/lw-readyroom.png',1100,980),
 'gruppen': uri(S+'/shots/lw-gruppen.png',1100),
 'rafpaper': uri(S+'/shots/raf-paper.png',1100,960),
 'lwpaper': uri(S+'/shots/lw-paper.png',1100,900),
 'record': uri(S+'/shots/personal-record.png',900),
 'sv109': uri(R+'/squadronroom/lw/aircraft/M109ULF_IIJG26_G_sideview.png',900),
 'sv110': uri(R+'/squadronroom/lw/aircraft/bf110-greygreen.png',900),
}
html=open(S+'/guide.tpl',encoding='utf-8').read()
for k,v in img.items(): html=html.replace('@@'+k+'@@',v)
assert '@@' not in html
open(S+'/modern-fix-handbook.html','w',encoding='utf-8').write(html)
print(len(html)//1024,'KB')
