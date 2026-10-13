#include "atlas_display.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

namespace godot {
namespace {
constexpr int KEEP = -32768;
constexpr double PI = 3.14159265358979323846;
bool image_size(int64_t w, int64_t h, int64_t size) {
    return w > 0 && h > 0 && w <= 8192 && h <= 8192 && w * h == size;
}
Dictionary error(const char *message) { Dictionary out; out["error"] = message; return out; }
int modulo(int value, int period) { return (value % period + period) % period; }
PackedByteArray bytes_of(const PackedFloat32Array &values) {
    PackedByteArray bytes; bytes.resize(values.size() * sizeof(float));
    if (!bytes.is_empty()) std::memcpy(bytes.ptrw(), values.ptr(), bytes.size());
    return bytes;
}
}

void NativeAtlasDisplay::_bind_methods() {
    ClassDB::bind_method(D_METHOD("api_version"), &NativeAtlasDisplay::api_version);
    ClassDB::bind_method(D_METHOD("paint_labels", "input"), &NativeAtlasDisplay::paint_labels);
    ClassDB::bind_method(D_METHOD("edge_field", "labels", "w", "h"), &NativeAtlasDisplay::edge_field);
    ClassDB::bind_method(D_METHOD("label_field", "regions", "ownership", "w", "h"), &NativeAtlasDisplay::label_field);
    ClassDB::bind_method(D_METHOD("label_rays", "field", "polity", "cell", "max_length", "hole"), &NativeAtlasDisplay::label_rays);
    ClassDB::bind_method(D_METHOD("fit_label", "rays", "sizes", "text_length"), &NativeAtlasDisplay::fit_label);
    ClassDB::bind_method(D_METHOD("label_tiles", "labels", "w", "h", "tile", "ids"), &NativeAtlasDisplay::label_tiles);
    ClassDB::bind_method(D_METHOD("region_tiles", "provinces", "regions", "w", "h", "tile"), &NativeAtlasDisplay::region_tiles);
}

Dictionary NativeAtlasDisplay::paint_labels(const Dictionary &input) const {
    const int w = input.get("w", 0), h = input.get("h", 0), tile = input.get("tile", 128);
    PackedInt32Array provinces = input.get("provinces", PackedInt32Array());
    PackedInt32Array ownership = input.get("ownership", PackedInt32Array());
    PackedByteArray weak = input.get("weak", PackedByteArray());
    PackedInt32Array previous = input.get("previous", PackedInt32Array());
    PackedInt32Array requested = input.get("dirty_tiles", PackedInt32Array());
    Array lines = input.get("lines", Array());
    if (!image_size(w,h,provinces.size()) || weak.size()!=provinces.size() || tile<1 || tile>512 || (!previous.is_empty() && previous.size()!=provinces.size())) return error("Invalid political raster dimensions");
    for (int i=0;i<provinces.size();++i) if (provinces[i]>=ownership.size()) return error("Invalid province reference");
    const int nx=(w+tile-1)/tile, ny=(h+tile-1)/tile;
    std::vector<uint8_t> dirty(nx*ny, previous.is_empty());
    for (int i=0;i<requested.size();++i) {
        if (requested[i]<0 || requested[i]>=nx*ny) return error("Invalid dirty tile");
        dirty[requested[i]]=1;
    }
    PackedInt32Array labels=previous;
    if (labels.is_empty()) labels.resize(w*h);
    int32_t *out=labels.ptrw();
    auto active=[&](int x,int y) { return dirty[(y/tile)*nx+x/tile]!=0; };
    for (int y=0;y<h;++y) for (int x=0;x<w;++x) if (active(x,y)) {
        const int region=provinces[y*w+x]; out[y*w+x]=region>=0?ownership[region]:-2;
    }
    std::vector<float> best(w*h,std::numeric_limits<float>::infinity());
    std::vector<int32_t> changed(w*h,KEEP);
    for (int line_index=0;line_index<lines.size();++line_index) {
        Dictionary line=lines[line_index]; PackedFloat32Array p=line.get("pts",PackedFloat32Array());
        if (p.size()%2) return error("Invalid boundary points");
        const int segs=p.size()/2-1;
        if (segs<1) continue;
        const bool closed=line.get("closed",false), end0=line.get("end0",false), end1=line.get("end1",false);
        const int left=line.get("left",-2), right=line.get("right",-2);
        std::vector<double> normals_x(segs),normals_y(segs);
        std::vector<uint8_t> near(segs,0);
        for (int i=0;i<segs;++i) {
            const double dx=double(p[2*i+2])-p[2*i],dy=double(p[2*i+3])-p[2*i+1];
            const double length=std::hypot(dx,dy);
            normals_x[i]=-dy/(length==0?1:length); normals_y[i]=dx/(length==0?1:length);
        }
        if (!closed) for (int ending=0;ending<2;++ending) {
            if (!(ending==0?end0:end1)) continue;
            double distance=0;
            for (int j=0;j<segs;++j) {
                if (distance>24) break;
                const int i=ending==0?j:segs-1-j;
                near[i]=1; const double dx=double(p[2*i+2])-p[2*i],dy=double(p[2*i+3])-p[2*i+1]; distance+=std::sqrt(dx*dx+dy*dy);
            }
        }
        const int back=std::min(segs,4);
        const double d0x=double(p[0])-p[2*back],d0y=double(p[1])-p[2*back+1];
        const double d1x=double(p[2*segs])-p[2*(segs-back)],d1y=double(p[2*segs+1])-p[2*(segs-back)+1];
        for (double shift:{0.,-double(w),double(w)}) for (int i=0;i<segs;++i) {
            const double reach=near[i]?8.:4.;
            const double ax=p[2*i]+shift,ay=p[2*i+1],bx=p[2*i+2]+shift,by=p[2*i+3];
            const double dx=bx-ax,dy=by-ay,length2=dx*dx+dy*dy,inv=length2>0?1./length2:0.;
            const int prior=i>0?i-1:(closed?segs-1:i),next=i+1<segs?i+1:(closed?0:i);
            const double n0x=normals_x[prior]+normals_x[i],n0y=normals_y[prior]+normals_y[i];
            const double n1x=normals_x[i]+normals_x[next],n1y=normals_y[i]+normals_y[next];
            const int x0=std::max(0,int(std::ceil(std::min(ax,bx)-reach-.5))),x1=std::min(w-1,int(std::floor(std::max(ax,bx)+reach-.5)));
            const int y0=std::max(0,int(std::ceil(std::min(ay,by)-reach-.5))),y1=std::min(h-1,int(std::floor(std::max(ay,by)+reach-.5)));
            for (int y=y0;y<=y1;++y) for (int x=x0;x<=x1;++x) {
                const int k=y*w+x;
                if (!active(x,y) || out[k]==-2) continue;
                const double px=x+.5,py=y+.5,t=((px-ax)*dx+(py-ay)*dy)*inv;
                double qx,qy,side;
                if (t<=0) { qx=ax-px; qy=ay-py; side=(px-ax)*n0x+(py-ay)*n0y; }
                else if (t>=1) { qx=bx-px; qy=by-py; side=(px-bx)*n1x+(py-by)*n1y; }
                else { qx=ax+dx*t-px; qy=ay+dy*t-py; side=dx*(py-ay)-dy*(px-ax); }
                const double d2=qx*qx+qy*qy,limit=near[i]&&weak[k]?64.:16.;
                if (d2>limit || d2>=best[k]) continue;
                best[k]=static_cast<float>(d2);
                const double ex0=px-(p[0]+shift),ey0=py-p[1],ex1=px-(p[2*segs]+shift),ey1=py-p[2*segs+1];
                const bool beyond=(end0 && ex0*d0x+ey0*d0y>0 && ex0*ex0+ey0*ey0<=limit)||(end1 && ex1*d1x+ey1*d1y>0 && ex1*ex1+ey1*ey1<=limit);
                changed[k]=beyond?KEEP:(side>0?left:right);
            }
        }
    }
    for (int i=0;i<w*h;++i) if (changed[i]!=KEEP) out[i]=changed[i];
    PackedInt32Array tiles; for (int i=0;i<nx*ny;++i) if (dirty[i]) tiles.append(i);
    Dictionary result; result["labels"]=labels; result["dirty_tiles"]=tiles; return result;
}

Dictionary NativeAtlasDisplay::edge_field(const PackedInt32Array &labels,int64_t width,int64_t height) const {
    if (!image_size(width,height,labels.size())) return error("Invalid edge field dimensions");
    const int w=width,h=height,gw0=(w+1)/2,gh=(h+1)/2,pad=34,gw=gw0+pad*2;
    std::vector<int32_t> lab(gw*gh);
    PackedFloat32Array distances; distances.resize(gw*gh); float *d=distances.ptrw();
    for (int y=0;y<gh;++y) for (int x=0;x<gw;++x) lab[y*gw+x]=labels[std::min(h-1,y*2+1)*w+std::min(w-1,modulo(x-pad,gw0)*2+1)];
    for (int y=0;y<gh;++y) for (int x=0;x<gw;++x) {
        const int k=y*gw+x,l=lab[k]; bool source=false;
        if (l!=-2) for (int q:{x>0?k-1:k,x<gw-1?k+1:k,y>0?k-gw:k,y<gh-1?k+gw:k}) if (lab[q]!=l && lab[q]!=-2) { source=true; break; }
        d[k]=source?.5f:1e6f;
    }
    const double diagonal=std::sqrt(2.);
    for (int y=0;y<gh;++y) for (int x=0;x<gw;++x) {
        const int k=y*gw+x; double value=d[k];
        if (x>0) value=std::min(value,double(d[k-1])+1.);
        if (y>0) { value=std::min(value,double(d[k-gw])+1.); if(x>0)value=std::min(value,double(d[k-gw-1])+diagonal); if(x<gw-1)value=std::min(value,double(d[k-gw+1])+diagonal); }
        d[k]=static_cast<float>(value);
    }
    for (int y=gh-1;y>=0;--y) for (int x=gw-1;x>=0;--x) {
        const int k=y*gw+x; double value=d[k];
        if (x<gw-1)value=std::min(value,double(d[k+1])+1.);
        if (y<gh-1) { value=std::min(value,double(d[k+gw])+1.); if(x<gw-1)value=std::min(value,double(d[k+gw+1])+diagonal); if(x>0)value=std::min(value,double(d[k+gw-1])+diagonal); }
        d[k]=static_cast<float>(value);
    }
    Dictionary out; out["w"]=gw;out["h"]=gh;out["bytes"]=bytes_of(distances);return out;
}

Dictionary NativeAtlasDisplay::label_field(const PackedInt32Array &regions,const PackedInt32Array &ownership,int64_t width,int64_t height) const {
    if (!image_size(width,height,regions.size())) return error("Invalid label field dimensions");
    const int w=width,h=height; PackedInt32Array owners;owners.resize(w*h);int32_t *owner=owners.ptrw();
    int nations=0;
    for (int i=0;i<w*h;++i) { if(regions[i]>=ownership.size())return error("Invalid region reference");owner[i]=regions[i]>=0?ownership[regions[i]]:-1;nations=std::max(nations,owner[i]+1); }
    if (nations>100000) return error("Invalid polity reference");
    PackedFloat32Array dist;dist.resize(w*h);float *d=dist.ptrw();
    for(int y=0;y<h;++y)for(int x=0;x<w;++x) {
        const int i=y*w+x,o=owner[i];double v=1e9;
        if(o<0){d[i]=0;continue;}
        if(y==0 || y==h-1)v=.5;
        else { const int l=y*w+modulo(x-1,w),r=y*w+modulo(x+1,w);
            if(owner[l]!=o || owner[r]!=o || owner[i-w]!=o || owner[i+w]!=o)v=.5;
            else if(owner[l-w]!=o || owner[r-w]!=o || owner[l+w]!=o || owner[r+w]!=o)v=.71;
        }
        d[i]=static_cast<float>(v);
    }
    const double diagonal=std::sqrt(2.);
    for(int pass=0;pass<2;++pass)for(bool reverse:{false,true}) {
        for(int y=reverse?h-2:1;reverse?y>0:y<h;y+=reverse?-1:1)for(int x=reverse?w-1:0;reverse?x>=0:x<w;x+=reverse?-1:1) {
            const int i=y*w+x,o=owner[i];if(o<0 || d[i]<=.5)continue;
            const int l=y*w+modulo(x-1,w),r=y*w+modulo(x+1,w),row=reverse?w:-w,side=reverse?r:l;
            const int indices[]={side,i+row,(reverse?r:l)+row,(reverse?l:r)+row};
            double v=d[i];for(int q=0;q<4;++q)if(owner[indices[q]]==o)v=std::min(v,double(d[indices[q]])+(q<2?1.:diagonal));
            d[i]=static_cast<float>(v);
        }
    }
    PackedInt32Array best;best.resize(nations);std::fill_n(best.ptrw(),nations,-1);
    std::vector<float> best_depth(nations,0);Array boxes;
    for(int p=0;p<nations;++p){Array box;box.push_back(w);box.push_back(h);box.push_back(-1);box.push_back(-1);boxes.push_back(box);}
    for(int i=0;i<w*h;++i) {
        d[i]=owner[i]<0?0.f:static_cast<float>(std::max(0.,(double(d[i])-.35)*4.));
        const int p=owner[i];if(p<0)continue;
        if(d[i]>best_depth[p]){best_depth[p]=d[i];best.set(p,i);}
        Array box=boxes[p];const int x=i%w,y=i/w;
        box[0]=std::min(int(box[0]),x);box[1]=std::min(int(box[1]),y);box[2]=std::max(int(box[2]),x);box[3]=std::max(int(box[3]),y);
    }
    Dictionary out;out["owner"]=owners;out["dist"]=dist;out["gw"]=w;out["gh"]=h;out["best"]=best;out["boxes"]=boxes;return out;
}

Dictionary NativeAtlasDisplay::label_rays(const Dictionary &field,int64_t polity,int64_t cell,double max_length,const Array &source_hole) const {
    const int w=field.get("gw",0),h=field.get("gh",0);PackedInt32Array owner=field.get("owner",PackedInt32Array());PackedFloat32Array dist=field.get("dist",PackedFloat32Array());
    if(!image_size(w,h,owner.size()) || dist.size()!=owner.size() || cell<0 || cell>=owner.size() || !std::isfinite(max_length) || max_length<0 || max_length>65536 || (!source_hole.is_empty() && source_hole.size()!=3))return error("Invalid label ray input");
    const double cx=cell%w+.5,cy=cell/w+.5;bool hole=!source_hole.is_empty();double hx=0,hy=0,hr=0;
    if(hole){hx=source_hole[0];hy=source_hole[1];hr=source_hole[2];double dx=hx-cx*4.;hx=cx*4.+dx-w*4.*std::floor(dx/(w*4.)+.5);}
    double depth=dist[cell];if(hole){const double dx=(cell%w+.5)*4.-double(source_hole[0]);const double wrapped=dx-w*4.*std::floor(dx/(w*4.)+.5),dy=(cell/w+.5)*4.-hy;depth=std::min(depth,std::max(0.,std::sqrt(wrapped*wrapped+dy*dy)-hr));}
    const int count=std::max(2,int(std::ceil(max_length/2.))+1);PackedFloat32Array profile;profile.resize(72*count);std::fill_n(profile.ptrw(),profile.size(),0.f);PackedInt32Array lengths;lengths.resize(72);
    float *prof=profile.ptrw();
    for(int r=0;r<72;++r) {
        const double angle=r*5.*PI/180.,co=std::cos(angle),si=std::sin(angle);double minimum=depth;int j=1;prof[r*count]=static_cast<float>(minimum);
        while(j<count) {
            const double x=cx+co*j*.5,y=cy+si*j*.5;const int gx=modulo(int(std::floor(x)),w),gy=int(std::floor(y));double value=0;
            if(gy>=0 && gy<h){const int i=gy*w+gx;if(owner[i]==polity){value=dist[i];if(hole){const double dx=x*4.-hx,dy=y*4.-hy;value=std::min(value,std::max(0.,std::sqrt(dx*dx+dy*dy)-hr));}}}
            minimum=std::min(minimum,value);prof[r*count+j]=static_cast<float>(minimum);if(minimum<=0)break;++j;
        }
        lengths.set(r,std::min(j+1,count));
    }
    Dictionary out;out["px"]=cx*4.;out["py"]=cy*4.;out["depth"]=depth;out["prof"]=profile;out["len"]=lengths;out["max_steps"]=count;return out;
}

Dictionary NativeAtlasDisplay::fit_label(const Dictionary &rays,const Array &sizes,int64_t text_length) const {
    const int count=rays.get("max_steps",0);const double depth=rays.get("depth",0.);PackedFloat32Array profile=rays.get("prof",PackedFloat32Array());PackedInt32Array lengths=rays.get("len",PackedInt32Array());
    if(count<2 || count>32769 || profile.size()!=72*count || lengths.size()!=72 || text_length<0)return error("Invalid label fit input");
    for(int r=0;r<72;++r)if(lengths[r]<1 || lengths[r]>count)return error("Invalid ray extent");
    auto reach=[&](int r,double height){const int base=r*count;int lo=0,hi=lengths[r]-1;if(profile[base]<height)return -1.;while(lo<hi){const int mid=(lo+hi+1)>>1;if(profile[base+mid]>=height)lo=mid;else hi=mid-1;}return lo*2.;};
    auto fit=[&](bool vertical){Dictionary best;
        for(int index=0;index<sizes.size();++index){const double size=sizes[index],height=size*.55+2.;if(!std::isfinite(size) || size<=0)continue;if(depth<height)continue;const double need=size*(1.8*(text_length-1)+1.);double best_score=-std::numeric_limits<double>::infinity();
            for(int i=0;i<72;++i){const double li=reach(i,height);if(li<0)continue;
                for(int delta=vertical?34:29;delta<=36;++delta){const int j=(i+delta)%72;const double lj=reach(j,height);if(lj<0 || li+lj<need)continue;
                    const double ia=i*5.*PI/180.,ja=j*5.*PI/180.;const double ax=std::cos(ia)*li,ay=std::sin(ia)*li,bx=std::cos(ja)*lj,by=std::sin(ja)*lj;
                    const double tilt=std::atan2(std::abs(by-ay),std::abs(bx-ax))*180./PI,turn=std::abs(180-delta*5);double weight;
                    if(vertical){if(tilt<72)continue;weight=1.-.3*std::pow((90.-tilt)/18.,2.);}else{if(tilt>25)continue;weight=1.-.5*std::pow(tilt/25.,2.);}
                    weight*=1.-.3*std::pow(turn/35.,2.);const double score=(li+lj)*weight*(1.+.1*std::min(li,lj)/std::max(std::max(li,lj),1e-6));
                    if(score>best_score){best_score=score;best["size"]=size;best["i"]=i;best["j"]=j;best["li"]=li;best["lj"]=lj;best["vertical"]=vertical;}
                }
            }
            if(!best.is_empty())return best;
        }
        return best;
    };
    Dictionary horizontal=fit(false),vertical=text_length>=2?fit(true):Dictionary();
    if(!vertical.is_empty() && (horizontal.is_empty() || double(vertical["size"])>=double(horizontal["size"])*1.25))return vertical;
    return horizontal.is_empty()?vertical:horizontal;
}

Array NativeAtlasDisplay::label_tiles(const PackedInt32Array &labels,int64_t w,int64_t h,int64_t tile,const PackedInt32Array &ids) const {
    Array out;if(!image_size(w,h,labels.size()) || tile<1 || tile>512)return out;const int nx=(w+tile-1)/tile,ny=(h+tile-1)/tile;
    for(int q=0;q<ids.size();++q){const int id=ids[q];if(id<0 || id>=nx*ny)return Array();PackedFloat32Array values;values.resize(tile*tile);float *pixels=values.ptrw();
        for(int y=0;y<tile;++y)for(int x=0;x<tile;++x){const int px=(id%nx)*tile+x,py=(id/nx)*tile+y;pixels[y*tile+x]=px<w && py<h?float(labels[py*w+px]):-2.f;}
        Dictionary row;row["id"]=id;row["bytes"]=bytes_of(values);out.push_back(row);
    }return out;
}

Array NativeAtlasDisplay::region_tiles(const PackedInt32Array &provinces,int64_t regions,int64_t w,int64_t h,int64_t tile) const {
    Array out;if(!image_size(w,h,provinces.size()) || tile<1 || tile>512 || regions<0 || regions>100000)return out;
    const int nx=(w+tile-1)/tile,ny=(h+tile-1)/tile;if(regions*nx*ny>100000000)return out;
    std::vector<uint8_t> present(regions*nx*ny,0);
    for(int y=0;y<h;++y)for(int x=0;x<w;++x){const int p=provinces[y*w+x];if(p>=regions)return Array();if(p>=0)present[p*nx*ny+(y/tile)*nx+x/tile]=1;}
    for(int p=0;p<regions;++p){PackedInt32Array list;for(int i=0;i<nx*ny;++i)if(present[p*nx*ny+i])list.append(i);out.push_back(list);}return out;
}
}
