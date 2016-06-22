#pragma once
#include "SceneRenderTask.h"
#include "DiscretePathRenderer.h"
#include "FullConnectedInterPixelRenderer.h"
#include "EuclideanPathRenderer.h"
#include "MagnifyRenderer.h"

using namespace Glyph3;
class Glyph3::Entity3D;

class ColorSmoothRenderTask : public SceneRenderTask
{
public:
	ColorSmoothRenderTask(RendererDX11 & Renderer, ResourcePtr RenderTarget, FLOAT magLevel);
	virtual ~ColorSmoothRenderTask();

	virtual void Update(float fTime);
	virtual void QueuePreTasks(RendererDX11* pRenderer);
	virtual void ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager);
	virtual void Resize(UINT width, UINT height);

	virtual void SetEntity(Glyph3::Entity3D* pEntity);
	virtual void SetScene(Scene* pScene);

	virtual void SetRenderParams(IParameterManager* pParamManager);
	virtual void SetUsageParams(IParameterManager* pParamManager);

	virtual std::wstring GetName();

	void SetMagnifyLevel(FLOAT lvl);

protected:
	int						ResolutionX;
	int						ResolutionY;

	int						m_discreteSurfWidth;
	int						m_discreteSurfHeight;

	int						m_iViewport;

	ResourcePtr				m_BackBuffer;
	ResourcePtr				m_DepthTarget;
	
	std::vector<ResourcePtr>	m_discretePathTargets;
	ResourcePtr					m_discretePathSurfaceDepthTarget;

	std::vector<ResourcePtr>	m_euclideanPathTarget;
	ResourcePtr					m_euclideanPathDepthTarget;

	DiscretePathRenderer*			m_pDiscretePathView;
	ShaderResourceParameterDX11*	m_pViewportSurfParam;
	ShaderResourceParameterDX11*	m_pDiscreteSurfParam;

	FullConnectedInterPixelRenderer* m_pFullConnectedPointView;
	ShaderResourceParameterDX11*	 m_pFullConnectedDiscreteSurfParam;
	std::vector<ResourcePtr>		 m_fullConnectedDiscretePathTargets;
	ResourcePtr						 m_fullConnectedDiscretePathDepthTarget;

	MagnifyRenderer*				m_pMagnifyView;
	ShaderResourceParameterDX11*	m_pMagnifySurfParam;
	ShaderResourceParameterDX11*	m_pMagnifyDefectSurfParam;
	std::vector<ResourcePtr>		m_magnifyTargets;
	ResourcePtr						m_magnifyDepthTarget;

	EuclideanPathRenderer*			m_pEuclideanPathView;
	ShaderResourceParameterDX11*	m_pEuclideanSurfParam;


	FLOAT						m_magnifyLevel;

	void UpdateDiscreteSurfDimension();
	void SetupViews();
};